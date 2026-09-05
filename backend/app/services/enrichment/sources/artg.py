"""
TGA Australian Register of Therapeutic Goods (ARTG) source.

TGA does not expose a stable public JSON API for ARTG lookups. The two
working options are:

  A. Public CSV export (the "ARTG full extract", published periodically).
     Best for batch enrichment — download once, look up in memory.

  B. Web search at https://www.tga.gov.au/products/artg/<id> for a single
     ARTG number. HTML scrape.

This connector implements (B) so it works without preloaded data. For
batch jobs, override `local_index_path` to point at a pre-parsed JSONL of
{artg_id, brand_name, sponsor, …} records and the connector serves from
that index in memory.
"""
from __future__ import annotations

import json
import logging
import re
from pathlib import Path
from typing import Optional

import httpx

from app.services.enrichment.normalizer import clean_text
from app.services.enrichment.sources.base import EnrichmentResult, EnrichmentSource

logger = logging.getLogger(__name__)

_TGA_ARTG_URL_FMT = "https://www.tga.gov.au/resources/artg/{artg_id}"
_HTTP_TIMEOUT     = 15.0


class ArtgSource(EnrichmentSource):

    source_name     = "tga_artg"
    BASE_CONFIDENCE = 0.95

    def __init__(self, local_index_path: str | None = None):
        super().__init__()
        self._index: dict[str, dict] | None = None
        if local_index_path:
            self._load_index(Path(local_index_path))

    def _load_index(self, path: Path) -> None:
        if not path.exists():
            logger.warning("[artg] index %s missing — falling back to web", path)
            return
        idx: dict[str, dict] = {}
        with path.open("r", encoding="utf-8") as f:
            for line in f:
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if row.get("artg_id"):
                    idx[str(row["artg_id"])] = row
        self._index = idx
        logger.info("[artg] loaded %d entries from %s", len(idx), path)

    async def fetch(self, *, medicine_id: int, **lookup_keys) -> EnrichmentResult:
        artg = lookup_keys.get("artg_id") or lookup_keys.get("tga_artg_number")
        if not artg:
            return self._none(reason="no_artg_id")

        # In-memory hit?
        if self._index is not None:
            row = self._index.get(str(artg))
            if row:
                return self._ok_from_row(row, artg)
            return self._none(reason="not_in_index")

        # No local index configured. The TGA public site lacks a stable
        # per-ARTG-id URL — every live scrape attempt either times out or
        # returns a search page we can't parse. Until ARTG_INDEX_PATH is
        # set in .env to a parsed ARTG CSV, fast-fail rather than burn
        # 15-30 seconds per medicine on doomed HTTP requests.
        return self._none(reason="no_local_index")

        # ─────────────────────────────────────────────────────────────────
        # Code below is preserved for the day the public URL pattern
        # stabilises. Not executed under current config.
        # Live HTML scrape.
        #
        # NOTE: the public TGA website does not expose a stable per-ARTG-id
        # URL — the search UI is JavaScript-driven against a Funnelback
        # backend. Until we wire either the ARTG full extract (CSV) into
        # `local_index_path` or a proven URL pattern, the live scrape is
        # best-effort and frequently returns no useful HTML. We log at
        # DEBUG to avoid spamming the operator on every miss; the
        # orchestrator falls through to the next source anyway.
        url = _TGA_ARTG_URL_FMT.format(artg_id=artg)
        try:
            async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT, follow_redirects=True) as client:
                resp = await client.get(url)
            if resp.status_code in (404, 410):
                return self._none(reason=str(resp.status_code))
            resp.raise_for_status()
        except Exception as exc:
            logger.debug("[artg] %s: %s for artg_id=%s",
                         type(exc).__name__, exc, artg)
            return self._err(exc)

        fields = self._parse_html(resp.text)
        if not fields:
            return self._none(reason="parse_empty")
        fields["tga_artg_number"] = str(artg)
        fields["tga_registered"]  = True
        return self._ok(
            fields=fields,
            field_confidence={f: self.BASE_CONFIDENCE for f in fields},
            evidence={"url": url},
        )

    # ── HTML extraction ──────────────────────────────────────────────────────

    _ROW_RE = re.compile(
        r"<dt[^>]*>\s*(?P<label>[^<]+?)\s*</dt>\s*<dd[^>]*>\s*(?P<value>.+?)\s*</dd>",
        re.IGNORECASE | re.DOTALL,
    )
    _LABEL_TO_FIELD = {
        "product name":         "brand_name",
        "active ingredients":   "active_ingredient",
        "active ingredient":    "active_ingredient",
        "sponsor":              "sponsor",
        "manufacturer":         "manufacturer",
        "dosage form":          "dosage_form",
        "registration status":  "registration_status",
        "approval date":        "approval_date",
        "registration type":    "approval_type",
    }

    def _parse_html(self, html: str) -> dict:
        out: dict = {}
        for m in self._ROW_RE.finditer(html):
            label = m.group("label").strip().lower()
            field = self._LABEL_TO_FIELD.get(label)
            if not field:
                continue
            value = clean_text(m.group("value"))
            if value:
                out.setdefault(field, value)
        return out

    def _ok_from_row(self, row: dict, artg: str) -> EnrichmentResult:
        fields = {
            "brand_name":         row.get("brand_name") or row.get("product_name"),
            "sponsor":            row.get("sponsor"),
            "manufacturer":       row.get("manufacturer"),
            "active_ingredient":  row.get("active_ingredient"),
            "dosage_form":        row.get("dosage_form"),
            "tga_artg_number":    str(artg),
            "tga_registered":     True,
            "approval_date":      row.get("approval_date"),
            "approval_type":      row.get("registration_type"),
        }
        fields = {k: v for k, v in fields.items() if v}
        return self._ok(
            fields=fields,
            field_confidence={f: self.BASE_CONFIDENCE for f in fields},
            evidence={"source_row": row.get("_source", "artg_index")},
        )
