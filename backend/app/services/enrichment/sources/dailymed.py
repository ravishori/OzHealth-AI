"""
DailyMed (US NIH) source — fallback only.

DailyMed is the US FDA's official SPL repository. For Australia-only data
it's lower priority than AMT/ARTG/PBS/HealthDirect, but it carries excellent
structured label text (indications, warnings, contraindications, adverse
reactions, pregnancy) for thousands of drugs that lack good AU coverage.

We look up by setid → label sections. If we don't have a setid we fall back
to a name search.
"""
from __future__ import annotations

import logging

import httpx

from app.services.enrichment.normalizer import clean_text
from app.services.enrichment.sources.base import EnrichmentResult, EnrichmentSource

logger = logging.getLogger(__name__)

_DAILYMED_BASE = "https://dailymed.nlm.nih.gov/dailymed/services/v2"
_HTTP_TIMEOUT  = 20.0


class DailyMedSource(EnrichmentSource):

    source_name     = "dailymed"
    BASE_CONFIDENCE = 0.70   # US-centric; lower for AU context

    async def fetch(self, *, medicine_id: int, **lookup_keys) -> EnrichmentResult:
        setid = lookup_keys.get("setid")
        name  = (
            lookup_keys.get("brand_name")
            or lookup_keys.get("generic_name")
            or lookup_keys.get("name")
        )
        if not setid and not name:
            return self._none(reason="no_lookup_key")

        try:
            if not setid:
                setid = await self._resolve_setid_by_name(name)
            if not setid:
                return self._none(reason="not_found")
            payload = await self._fetch_spl(setid)
        except Exception as exc:
            logger.warning("[dailymed] %s", exc)
            return self._err(exc)

        if not payload:
            return self._none(reason="empty_spl")
        fields = self._extract_fields(payload)
        return self._ok(
            fields=fields,
            field_confidence={f: self.BASE_CONFIDENCE for f in fields},
            evidence={"setid": setid,
                      "url": f"https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid={setid}"},
        )

    # ── Lookups ──────────────────────────────────────────────────────────────

    async def _resolve_setid_by_name(self, name: str) -> str | None:
        async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT) as client:
            resp = await client.get(
                f"{_DAILYMED_BASE}/spls.json",
                params={"drug_name": name, "pagesize": 1},
            )
        if resp.status_code != 200:
            return None
        data = resp.json().get("data") or []
        return data[0]["setid"] if data else None

    async def _fetch_spl(self, setid: str) -> dict | None:
        async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT) as client:
            resp = await client.get(f"{_DAILYMED_BASE}/spls/{setid}.json")
        if resp.status_code != 200:
            return None
        return (resp.json().get("data") or {})

    # ── Field extraction ─────────────────────────────────────────────────────

    _SECTION_TO_FIELD = {
        "indications & usage":            "uses",
        "indications and usage":          "uses",
        "dosage & administration":        "standard_dosage",
        "dosage and administration":      "standard_dosage",
        "adverse reactions":              "side_effects",
        "warnings":                       "warnings",
        "warnings and precautions":       "warnings",
        "boxed warning":                  "warnings",
        "contraindications":              "contraindications",
        "drug interactions":              "interactions",
        "use in specific populations":    "pregnancy_warning",
        "pregnancy":                      "pregnancy_warning",
        "nursing mothers":                "breastfeeding_warning",
        "lactation":                      "breastfeeding_warning",
        "storage and handling":           "storage_instructions",
        "how supplied/storage and handling": "storage_instructions",
    }

    def _extract_fields(self, payload: dict) -> dict:
        fields: dict = {}
        for s in payload.get("sections") or []:
            title = (s.get("title") or "").strip().lower()
            field = self._SECTION_TO_FIELD.get(title)
            if not field:
                continue
            text = clean_text(s.get("text") or s.get("plain_text"))
            if text:
                fields.setdefault(field, text)

        if payload.get("title") and "name" not in fields:
            fields["name"] = clean_text(payload["title"])
        return fields
