"""
Australian Medicines Terminology (AMT) — SNOMED CT-AU subset.

Authoritative for AU clinical terminology (concept IDs, brand/generic
mappings, ingredient lists, dosage forms). Access is via the National
Clinical Terminology Service (NCTS) FHIR endpoints which require a free
authenticated account.

This connector is a thin stub. Wire your NCTS bearer token via
`settings.NCTS_API_KEY` and the orchestrator picks it up automatically.
Until credentials are provided, the source returns `found=False` and the
orchestrator falls through to the next priority source.

NCTS endpoints (FHIR R4):
    GET https://api.healthterminologies.gov.au/syndication/v1/syndication.xml
    GET https://api.healthterminologies.gov.au/fhir/R4/CodeSystem
"""
from __future__ import annotations

import logging

import httpx

from app.services.enrichment.normalizer import clean_text
from app.services.enrichment.sources.base import EnrichmentResult, EnrichmentSource

logger = logging.getLogger(__name__)

_NCTS_BASE     = "https://api.healthterminologies.gov.au/fhir/R4"
_HTTP_TIMEOUT  = 15.0


class AmtSource(EnrichmentSource):

    source_name     = "amt"
    BASE_CONFIDENCE = 0.97

    def __init__(self, bearer_token: str | None = None):
        super().__init__()
        self.token = bearer_token

    async def fetch(self, *, medicine_id: int, **lookup_keys) -> EnrichmentResult:
        if not self.token:
            return self._none(reason="no_ncts_token")

        amt   = lookup_keys.get("amt_code")
        name  = (
            lookup_keys.get("brand_name")
            or lookup_keys.get("generic_name")
            or lookup_keys.get("name")
        )
        if not amt and not name:
            return self._none(reason="no_lookup_key")

        headers = {
            "Authorization": f"Bearer {self.token}",
            "Accept":        "application/fhir+json",
        }
        try:
            async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT, headers=headers) as client:
                if amt:
                    # Direct concept lookup.
                    resp = await client.get(
                        f"{_NCTS_BASE}/CodeSystem/$lookup",
                        params={
                            "system": "http://snomed.info/sct",
                            "code":   amt,
                            "property": "all",
                        },
                    )
                else:
                    # Free-text search via ValueSet $expand against AMT.
                    resp = await client.get(
                        f"{_NCTS_BASE}/ValueSet/$expand",
                        params={
                            "url":    "http://snomed.info/sct?fhir_vs=ecl/<<30605011000036107",
                            "filter": name,
                            "count":  1,
                        },
                    )
            resp.raise_for_status()
        except Exception as exc:
            logger.warning("[amt] %s", exc)
            return self._err(exc)

        data = resp.json()
        fields = self._parse(data, amt_hint=amt)
        if not fields:
            return self._none(reason="parse_empty")

        return self._ok(
            fields=fields,
            field_confidence={f: self.BASE_CONFIDENCE for f in fields},
            evidence={"snomed_amt_code": fields.get("amt_code", amt)},
        )

    # ── Parser ───────────────────────────────────────────────────────────────
    def _parse(self, payload: dict, *, amt_hint: str | None) -> dict:
        out: dict = {}

        # $lookup returns a Parameters resource with a `parameter` array.
        for param in payload.get("parameter") or []:
            name = param.get("name")
            if name == "display":
                out["name"] = clean_text(param.get("valueString"))
            elif name == "designation":
                # Each designation has a `use` and a `value`.
                parts = {p["name"]: p.get("valueString") or p.get("valueCode")
                         for p in param.get("part", [])}
                value = parts.get("value")
                use   = (parts.get("use") or "").lower()
                if "preferred" in use and value:
                    out.setdefault("generic_name", clean_text(value))

        # $expand returns a ValueSet with `expansion.contains`.
        for c in (payload.get("expansion") or {}).get("contains", []):
            out.setdefault("amt_code", c.get("code"))
            out.setdefault("name",     clean_text(c.get("display")))

        if amt_hint and "amt_code" not in out:
            out["amt_code"] = amt_hint
        return out
