"""
HealthDirect Australia source.

HealthDirect (healthdirect.gov.au) is the Australian Government's consumer
medicine portal. URLs look like:
    https://www.healthdirect.gov.au/medicines/brand/amt,3542011000036101/abilify

When we have an AMT code we go direct; otherwise we use the site search.

This is a polite HTML scraper. HealthDirect publishes consumer text under a
stable structured layout, but they don't expose a public JSON API — we parse
the HTML defensively and degrade gracefully on layout changes.
"""
from __future__ import annotations

import logging
import re
from urllib.parse import quote

import httpx

from app.services.enrichment.normalizer import clean_text, join_list
from app.services.enrichment.sources.base import EnrichmentResult, EnrichmentSource

logger = logging.getLogger(__name__)

_HD_BASE       = "https://www.healthdirect.gov.au"
_HTTP_TIMEOUT  = 20.0
_UA            = (
    "Mozilla/5.0 (AuHealth-AI/1.0; +https://aushealth.example/about) "
    "Healthdirect-enrichment-bot"
)


class HealthDirectSource(EnrichmentSource):

    source_name     = "healthdirect"
    BASE_CONFIDENCE = 0.88

    async def fetch(self, *, medicine_id: int, **lookup_keys) -> EnrichmentResult:
        # HealthDirect doesn't index complementary medicines / supplements —
        # the orchestrator flags them via `is_supplement`. Fast-fail saves
        # one ~3s search round trip per row.
        if lookup_keys.get("is_supplement"):
            return self._none(reason="supplement")

        amt = lookup_keys.get("amt_code")
        name = (
            lookup_keys.get("brand_name")
            or lookup_keys.get("generic_name")
            or lookup_keys.get("name")
        )
        if not amt and not name:
            return self._none(reason="no_lookup_key")

        url = await self._resolve_url(amt=amt, name=name)
        if not url:
            return self._none(reason="not_found")

        try:
            async with httpx.AsyncClient(
                timeout=_HTTP_TIMEOUT, headers={"User-Agent": _UA},
                follow_redirects=True,
            ) as client:
                resp = await client.get(url)
            resp.raise_for_status()
        except Exception as exc:
            logger.warning("[healthdirect] fetch %s failed: %s", url, exc)
            return self._err(exc)

        html = resp.text
        parsed = self._parse(html)
        if not parsed:
            return self._none(reason="parse_empty")
        return self._ok(
            fields=parsed,
            field_confidence={f: self.BASE_CONFIDENCE for f in parsed},
            evidence={"url": url},
        )

    # ── URL resolution ───────────────────────────────────────────────────────

    async def _resolve_url(self, *, amt: str | None, name: str | None) -> str | None:
        """Best-effort URL discovery."""
        if amt:
            # We don't know the slug, so try the discovery endpoint first.
            return f"{_HD_BASE}/medicines/brand/amt,{amt}"

        # No AMT — use the site search and pick the first /medicines/ result.
        try:
            async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT, headers={"User-Agent": _UA}) as client:
                resp = await client.get(
                    f"{_HD_BASE}/search",
                    params={"query": name, "section": "medicines"},
                    follow_redirects=True,
                )
            resp.raise_for_status()
        except Exception as exc:
            logger.warning("[healthdirect] search failed: %s", exc)
            return None

        m = re.search(r'href="(/medicines/[^"#]+)"', resp.text)
        return f"{_HD_BASE}{m.group(1)}" if m else None

    # ── HTML parsing ─────────────────────────────────────────────────────────
    # HealthDirect uses semantic <section> blocks with h2 headers. We grab the
    # text under each known heading. Layout-aware but resilient — missing
    # sections are silently skipped.

    _SECTION_RE = re.compile(
        r"<h2[^>]*>\s*(?P<title>[^<]+?)\s*</h2>\s*(?P<body>.*?)(?=<h2|</section|</main)",
        re.IGNORECASE | re.DOTALL,
    )
    _TITLE_TO_FIELD = {
        "what it is used for":              "uses",
        "what is it used for":              "uses",
        "indications":                       "uses",
        "warnings":                          "warnings",
        "before you take":                   "warnings",
        "side effects":                      "side_effects",
        "directions":                        "standard_dosage",
        "how to take":                       "standard_dosage",
        "dosage":                            "standard_dosage",
        "storage":                           "storage_instructions",
        "storage information":               "storage_instructions",
        "pregnancy":                         "pregnancy_warning",
        "pregnancy and breastfeeding":       "pregnancy_warning",
        "breastfeeding":                     "breastfeeding_warning",
        "consumer medicine information":     "consumer_information",
    }

    def _parse(self, html: str) -> dict:
        out: dict = {}

        # Top-of-page name + generic — usually in <h1> and a sibling lead-in.
        m = re.search(r"<h1[^>]*>\s*(?P<name>[^<]+?)\s*</h1>", html, re.IGNORECASE)
        if m:
            out["name"] = clean_text(m.group("name"))

        m = re.search(
            r"active ingredient[s]?:?\s*</[^>]+>\s*<[^>]+>([^<]+)<",
            html, re.IGNORECASE,
        )
        if m:
            ingredient = clean_text(m.group(1))
            if ingredient:
                out["generic_name"]      = ingredient
                out["active_ingredient"] = ingredient

        # Section-wise extraction.
        for match in self._SECTION_RE.finditer(html):
            title = match.group("title").strip().lower()
            field = self._TITLE_TO_FIELD.get(title)
            if not field:
                continue
            text = clean_text(match.group("body"))
            if not text:
                continue
            # Lists → comma-joined string.
            list_items = re.findall(r"<li[^>]*>(.*?)</li>", match.group("body"), re.IGNORECASE | re.DOTALL)
            if list_items:
                joined = join_list([clean_text(li) for li in list_items])
                if joined:
                    text = joined
            out.setdefault(field, text)

        # Pull a hero image if present.
        m = re.search(r'<img[^>]+src="(/[^"]+medicines[^"]+\.(?:png|jpg|jpeg|svg))"', html, re.IGNORECASE)
        if m:
            out["image_url"] = f"{_HD_BASE}{m.group(1)}"

        return out
