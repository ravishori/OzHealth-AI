"""
AI enrichment for medicines.

One concrete responsibility: given a medicine (or an unknown query string),
produce a structured AI payload that the cache can store and the API can
return. Pure function of inputs — knows nothing about Redis, cache TTLs, or
external sources.
"""
from __future__ import annotations

import json
import logging
from typing import Any

import anthropic

from app.core.config import settings
from app.models.medicine import Medicine

logger = logging.getLogger(__name__)

# Bump this when the prompt or response schema changes — old cache rows
# whose prompt_version != CURRENT will be picked up by the nightly worker.
CURRENT_PROMPT_VERSION = "v1.0"

_MODEL_FAST = "claude-haiku-4-5-20251001"   # cheap; structured JSON

_SYSTEM_PROMPT = """You are an Australian pharmaceutical information service.
Produce concise, evidence-based JSON-only answers about a medicine.
Reference TGA (Therapeutic Goods Administration) standards where relevant.
Never diagnose; always recommend a healthcare professional for individual advice.
Output MUST be valid JSON conforming exactly to the schema below — no prose,
no markdown, no leading/trailing text.
"""

_RESPONSE_SCHEMA_GUIDE = """{
  "summary":             "1–2 sentence plain-English overview",
  "patient_explanation": "3–4 sentences a patient would understand",
  "dosage_summary":      "typical adult dose; how often; with/without food",
  "side_effect_summary": "common side effects (3–6 bullets joined by '; ')",
  "warning_summary":     "key warnings, contraindications, drug interactions",
  "pregnancy_note":      "TGA pregnancy category statement, or 'data limited'",
  "faqs": [
    {"q": "...", "a": "..."},
    {"q": "...", "a": "..."},
    {"q": "...", "a": "..."}
  ]
}"""


class MedicineEnrichmentService:
    """Wraps the Anthropic call. Idempotent for a given input."""

    def __init__(self):
        self._client: anthropic.AsyncAnthropic | None = None
        if settings.ANTHROPIC_API_KEY and not settings.ANTHROPIC_API_KEY.startswith("your-"):
            self._client = anthropic.AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)

    # ── Public API ──────────────────────────────────────────────────────────

    async def enrich_known_medicine(self, m: Medicine) -> dict[str, Any]:
        """Enrichment for a medicine row that already exists in our DB."""
        prompt = self._prompt_for_medicine(m)
        return await self._call(prompt, label=f"med#{m.id}")

    async def enrich_unknown_query(self, query: str) -> dict[str, Any]:
        """Enrichment for a query we couldn't match locally."""
        prompt = (
            f"The user searched for the medicine: {query!r}.\n"
            f"Identify what drug this most likely refers to (consider brand "
            f"names, generic names, common misspellings), then produce the "
            f"information payload."
        )
        return await self._call(prompt, label=f"query_len:{len(query or '')}")

    # ── Internals ───────────────────────────────────────────────────────────

    def _prompt_for_medicine(self, m: Medicine) -> str:
        seed = [
            f"Medicine name: {m.name}",
            f"Generic name: {m.generic_name or 'unknown'}",
            f"Drug class: {m.drug_class or 'unknown'}",
            f"Composition: {m.composition or 'unknown'}",
            f"Standard dosage hint: {m.standard_dosage or 'unknown'}",
            f"Australian schedule: {m.schedule or 'unknown'}",
        ]
        return (
            "Produce the information payload for the medicine described below.\n\n"
            + "\n".join(seed)
        )

    async def _call(self, user_prompt: str, *, label: str) -> dict[str, Any]:
        if self._client is None:
            logger.warning("[enrichment:%s] no ANTHROPIC_API_KEY — returning stub", label)
            return self._stub_payload()

        try:
            resp = await self._client.messages.create(
                model       = _MODEL_FAST,
                max_tokens  = 1024,
                system      = _SYSTEM_PROMPT,
                messages    = [{
                    "role": "user",
                    "content": (
                        f"{user_prompt}\n\n"
                        f"Respond with JSON matching this schema:\n"
                        f"{_RESPONSE_SCHEMA_GUIDE}"
                    ),
                }],
            )
            text = resp.content[0].text.strip()
            # Defensive JSON unwrap (Claude occasionally wraps in ```json fences).
            if text.startswith("```"):
                text = text.strip("`")
                if text.lower().startswith("json"):
                    text = text[4:].lstrip()
            return json.loads(text)
        except json.JSONDecodeError as e:
            logger.error("[enrichment:%s] AI returned invalid JSON: %s", label, e)
            return self._stub_payload(error="invalid_json")
        except Exception as e:
            logger.exception("[enrichment:%s] AI call failed: %s", label, e)
            return self._stub_payload(error=str(e))

    @staticmethod
    def _stub_payload(error: str | None = None) -> dict[str, Any]:
        """Returned when the LLM isn't reachable — keeps the API contract intact."""
        return {
            "summary":             "AI enrichment unavailable.",
            "patient_explanation": "",
            "dosage_summary":      "",
            "side_effect_summary": "",
            "warning_summary":     "",
            "pregnancy_note":      "",
            "faqs": [],
            "_error": error,
        }


# Module-level singleton — Anthropic client is thread-safe and reuses HTTP.
enrichment_service = MedicineEnrichmentService()
