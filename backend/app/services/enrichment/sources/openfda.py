"""
OpenFDA source — final fallback.

OpenFDA's /drug/label.json endpoint is the same dataset DailyMed exposes,
just with a different query syntax. Useful when DailyMed search fails to
resolve a setid by name (it sometimes does for obscure compounded drugs).
"""
from __future__ import annotations

import logging

import httpx

from app.services.enrichment.normalizer import clean_text
from app.services.enrichment.sources.base import EnrichmentResult, EnrichmentSource

logger = logging.getLogger(__name__)

_OPENFDA_LABEL = "https://api.fda.gov/drug/label.json"
_HTTP_TIMEOUT  = 20.0


class OpenFdaSource(EnrichmentSource):

    source_name     = "openfda"
    BASE_CONFIDENCE = 0.68

    def __init__(self, api_key: str | None = None):
        super().__init__()
        self.api_key = api_key

    async def fetch(self, *, medicine_id: int, **lookup_keys) -> EnrichmentResult:
        name = (
            lookup_keys.get("brand_name")
            or lookup_keys.get("generic_name")
            or lookup_keys.get("name")
        )
        if not name:
            return self._none(reason="no_lookup_key")

        # OpenFDA's search syntax: openfda.brand_name:"Panadol" OR generic_name…
        query = f'(openfda.brand_name:"{name}"+openfda.generic_name:"{name}")'
        params: dict = {"search": query, "limit": 1}
        if self.api_key:
            params["api_key"] = self.api_key

        try:
            async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT) as client:
                resp = await client.get(_OPENFDA_LABEL, params=params)
            if resp.status_code == 404:
                return self._none(reason="404")
            resp.raise_for_status()
        except Exception as exc:
            logger.warning("[openfda] %s", exc)
            return self._err(exc)

        results = (resp.json() or {}).get("results") or []
        if not results:
            return self._none(reason="empty")

        fields = self._extract(results[0])
        return self._ok(
            fields=fields,
            field_confidence={f: self.BASE_CONFIDENCE for f in fields},
            evidence={"set_id": results[0].get("set_id"),
                      "spl_id": results[0].get("id")},
        )

    @staticmethod
    def _first(v):
        if isinstance(v, list):
            return v[0] if v else None
        return v

    def _extract(self, label: dict) -> dict:
        out: dict = {}
        of = label.get("openfda") or {}

        if of.get("brand_name"):    out["brand_name"]   = self._first(of["brand_name"])
        if of.get("generic_name"):  out["generic_name"] = self._first(of["generic_name"])
        if of.get("substance_name"):out["active_ingredient"] = ", ".join(of["substance_name"])
        if of.get("route"):         out["route"]        = self._first(of["route"])

        # Direct label sections (each is a single-string array in OpenFDA).
        mapping = {
            "indications_and_usage":      "uses",
            "dosage_and_administration":  "standard_dosage",
            "adverse_reactions":          "side_effects",
            "warnings":                   "warnings",
            "warnings_and_cautions":      "warnings",
            "contraindications":          "contraindications",
            "drug_interactions":          "interactions",
            "pregnancy":                  "pregnancy_warning",
            "nursing_mothers":            "breastfeeding_warning",
            "storage_and_handling":       "storage_instructions",
            "how_supplied":               "storage_instructions",
        }
        for src_key, dst_key in mapping.items():
            text = clean_text(self._first(label.get(src_key)))
            if text:
                out.setdefault(dst_key, text)
        return out
