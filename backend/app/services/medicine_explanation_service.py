"""
Minimum medicine explanation — database facts + constrained AI rephrase only.

AI must NOT invent indications, dosage, contraindications, interactions,
side effects, or warnings. Missing authoritative fields return the fixed
unavailable string.
"""
from __future__ import annotations

import json
import logging
import re
from typing import Any, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.medicine import Medicine
from app.models.medicine_search_models import MedicineIngredientStrength, PbsListing
from app.services.ai_service import _ai_available, _new_client, _MODEL_HAIKU
from app.core.logging_config import ai_log

logger = logging.getLogger(__name__)

UNAVAILABLE = (
    "Information not available in the current Australian medicine dataset."
)

_DISCLAIMER = (
    "This explanation is for information only and is not medical advice. "
    "Always confirm with a registered healthcare professional. "
    "AI text only rephrases database fields supplied below — it is not a "
    "source of clinical facts."
)


def _nonempty(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        s = value.strip()
        return bool(s) and s.lower() not in {"null", "none", "n/a", "[]", "{}"}
    if isinstance(value, (list, dict)):
        return len(value) > 0
    return True


def _parse_jsonish(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (list, dict)):
        return value
    if isinstance(value, str):
        s = value.strip()
        if not s:
            return None
        try:
            return json.loads(s)
        except Exception:
            return value
    return value


def _section(
    text: Optional[str],
    *,
    source: str,
    available: bool,
) -> dict[str, Any]:
    if not available or not _nonempty(text):
        return {
            "text": UNAVAILABLE,
            "available": False,
            "source": "unavailable",
        }
    return {
        "text": text.strip() if isinstance(text, str) else str(text),
        "available": True,
        "source": source,  # database | ai_rephrased_from_database
    }


class MedicineExplanationService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def explain(self, medicine_id: int) -> dict[str, Any]:
        med = await self.db.get(Medicine, medicine_id)
        if med is None:
            raise LookupError(f"medicine_id {medicine_id} not found")

        ingredients = await self._ingredients(medicine_id)
        pbs_listings = await self._pbs(medicine_id)
        facts = self._database_facts(med, ingredients, pbs_listings)

        # Clinical sections: ONLY from authoritative DB columns
        se_raw = med.side_effects if _nonempty(med.side_effects) else None
        warn_raw = med.warnings if _nonempty(med.warnings) else None
        uses_raw = med.uses if _nonempty(med.uses) else None
        # therapeutic_class / drug_class may support "what it is" / how it works framing
        class_raw = (
            med.therapeutic_class
            if _nonempty(med.therapeutic_class)
            else (med.drug_class if _nonempty(med.drug_class) else None)
        )
        composition = med.composition if _nonempty(med.composition) else None
        active = med.active_ingredient if _nonempty(med.active_ingredient) else None

        # Deterministic identity sections (always database)
        brand = med.brand_name
        if not _nonempty(brand):
            brands = _parse_jsonish(med.brand_names)
            if isinstance(brands, list) and brands:
                brand = brands[0] if isinstance(brands[0], str) else str(brands[0])
            elif isinstance(brands, str):
                brand = brands
            else:
                brand = None

        dosage_form = med.dosage_form
        if not _nonempty(dosage_form):
            forms = _parse_jsonish(med.dosage_forms)
            if isinstance(forms, list) and forms:
                dosage_form = forms[0] if isinstance(forms[0], str) else str(forms[0])
            elif forms is not None:
                dosage_form = str(forms)

        identity = {
            "medicine_id": med.id,
            "medicine_name": med.name,
            "generic_name": med.generic_name,
            "brand_name": brand,
            "strength": med.strength,
            "dosage_form": dosage_form,
            "route": med.route,
            "release_type": getattr(med, "release_type", None),
            "coating_type": getattr(med, "coating_type", None),
            "ingredients": ingredients,
            "source": "database",
        }

        tga_pbs = {
            "tga_artg_number": med.tga_artg_number,
            "tga_registered": med.tga_registered,
            "registration_status": med.registration_status,
            "sponsor": med.sponsor or med.manufacturer,
            "pbs_code": med.pbs_code,
            "pbs_listing_date": med.pbs_listing_date.isoformat()
            if getattr(med, "pbs_listing_date", None)
            else None,
            "pbs_listings": pbs_listings,
            "data_source": med.data_source,
            "primary_source": getattr(med, "primary_source", None),
            "schedule": med.schedule,
            "atc_code": med.atc_code,
            "source": "database",
        }

        # Build plain-English sections — AI only rephrases supplied facts
        ai_parts = await self._rephrase_safe(
            facts=facts,
            has_uses=bool(uses_raw),
            has_side_effects=bool(se_raw),
            has_warnings=bool(warn_raw),
            has_class=bool(class_raw),
            uses_raw=uses_raw,
            side_effects_raw=se_raw,
            warnings_raw=warn_raw,
            class_raw=class_raw,
            composition=composition,
            active=active,
        )

        what_it_is = _section(
            ai_parts.get("what_it_is") or self._fallback_what_it_is(facts),
            source="ai_rephrased_from_database"
            if ai_parts.get("what_it_is") and ai_parts.get("ai_used")
            else "database",
            available=True,  # always can describe identity from DB name/form
        )

        what_used = _section(
            ai_parts.get("what_it_is_used_for") if uses_raw or class_raw else None,
            source="ai_rephrased_from_database"
            if (uses_raw or class_raw) and ai_parts.get("what_it_is_used_for") and ai_parts.get("ai_used")
            else ("database" if (uses_raw or class_raw) else "unavailable"),
            available=bool(uses_raw or class_raw),
        )
        if (uses_raw or class_raw) and not what_used["available"]:
            # Template fallback from class only — still database-sourced
            what_used = _section(
                self._fallback_used_for(uses_raw, class_raw),
                source="database",
                available=True,
            )

        how_works = _section(
            ai_parts.get("how_it_works") if class_raw or composition else None,
            source="ai_rephrased_from_database"
            if (class_raw or composition) and ai_parts.get("how_it_works") and ai_parts.get("ai_used")
            else ("database" if (class_raw or composition) else "unavailable"),
            available=bool(class_raw or composition),
        )
        if (class_raw or composition) and how_works["source"] == "unavailable":
            how_works = _section(
                self._fallback_how_it_works(class_raw, composition),
                source="database",
                available=True,
            )

        important = _section(
            ai_parts.get("important_information") or self._fallback_important(facts, tga_pbs),
            source="ai_rephrased_from_database"
            if ai_parts.get("important_information") and ai_parts.get("ai_used")
            else "database",
            available=True,
        )

        side_effects = _section(
            ai_parts.get("common_side_effects") if se_raw else None,
            source="ai_rephrased_from_database"
            if se_raw and ai_parts.get("common_side_effects") and ai_parts.get("ai_used")
            else ("database" if se_raw else "unavailable"),
            available=bool(se_raw),
        )
        if se_raw and side_effects["source"] == "unavailable":
            side_effects = _section(str(se_raw), source="database", available=True)

        warnings = _section(
            ai_parts.get("warnings") if warn_raw else None,
            source="ai_rephrased_from_database"
            if warn_raw and ai_parts.get("warnings") and ai_parts.get("ai_used")
            else ("database" if warn_raw else "unavailable"),
            available=bool(warn_raw),
        )
        if warn_raw and warnings["source"] == "unavailable":
            warnings = _section(str(warn_raw), source="database", available=True)

        return {
            "medicine_id": med.id,
            "confirmed_medicine": True,
            "medicine_name": identity["medicine_name"],
            "generic_name": identity["generic_name"],
            "brand_name": identity["brand_name"],
            "strength": identity["strength"],
            "dosage_form": identity["dosage_form"],
            "route": identity["route"],
            "what_it_is": what_it_is,
            "what_it_is_used_for": what_used,
            "how_it_works": how_works,
            "important_information": important,
            "common_side_effects": side_effects,
            "warnings": warnings,
            "tga_pbs": tga_pbs,
            "ingredients": ingredients,
            "database_facts": facts,
            "ai": {
                "used": bool(ai_parts.get("ai_used")),
                "role": "rephrase_database_fields_only",
                "provider": "anthropic" if _ai_available() else None,
                "invented_clinical_facts": False,
            },
            "safety": {
                "disclaimer": _DISCLAIMER,
                "ocr_note": (
                    "Only call this endpoint with a confirmed catalog medicine_id "
                    "(e.g. after OCR → catalog match). Never explain unconfirmed OCR text."
                ),
                "unavailable_placeholder": UNAVAILABLE,
            },
        }

    async def _ingredients(self, medicine_id: int) -> list[dict]:
        stmt = (
            select(MedicineIngredientStrength)
            .where(MedicineIngredientStrength.medicine_id == medicine_id)
            .order_by(
                MedicineIngredientStrength.position,
                MedicineIngredientStrength.ingredient_strength_id,
            )
        )
        rows = list((await self.db.execute(stmt)).scalars().all())
        return [
            {
                "name": r.ingredient_name,
                "role": r.ingredient_role,
                "strength_value": float(r.strength_value)
                if r.strength_value is not None
                else None,
                "strength_unit": r.strength_unit,
                "source": r.source,
            }
            for r in rows
        ]

    async def _pbs(self, medicine_id: int) -> list[dict]:
        stmt = select(PbsListing).where(PbsListing.medicine_id == medicine_id)
        rows = list((await self.db.execute(stmt)).scalars().all())
        return [
            {
                "pbs_code": r.pbs_code,
                "program_code": r.program_code,
                "restriction_level": r.restriction_level,
                "max_quantity": r.max_quantity,
                "repeats_allowed": r.repeats_allowed,
                "effective_date": r.effective_date.isoformat()
                if r.effective_date
                else None,
                "is_active": r.is_active,
            }
            for r in rows
        ]

    def _database_facts(
        self,
        med: Medicine,
        ingredients: list[dict],
        pbs_listings: list[dict],
    ) -> dict[str, Any]:
        """Only non-empty catalog fields — this is the sole allowed AI input."""
        facts: dict[str, Any] = {
            "medicine_id": med.id,
            "name": med.name,
        }
        for key, val in {
            "generic_name": med.generic_name,
            "brand_name": med.brand_name,
            "active_ingredient": med.active_ingredient,
            "strength": med.strength,
            "dosage_form": med.dosage_form,
            "dosage_forms": med.dosage_forms,
            "route": med.route,
            "release_type": getattr(med, "release_type", None),
            "coating_type": getattr(med, "coating_type", None),
            "composition": med.composition,
            "therapeutic_class": med.therapeutic_class,
            "drug_class": med.drug_class,
            "uses": med.uses,
            "side_effects": med.side_effects,
            "warnings": med.warnings,
            "schedule": med.schedule,
            "tga_artg_number": med.tga_artg_number,
            "tga_registered": med.tga_registered,
            "pbs_code": med.pbs_code,
            "sponsor": med.sponsor or med.manufacturer,
            "data_source": med.data_source,
            "primary_source": getattr(med, "primary_source", None),
            "registration_status": med.registration_status,
            "atc_code": med.atc_code,
        }.items():
            if _nonempty(val):
                facts[key] = val if not isinstance(val, bool) else val
        if ingredients:
            facts["ingredients"] = ingredients
        if pbs_listings:
            facts["pbs_listings"] = pbs_listings
        return facts

    async def _rephrase_safe(
        self,
        *,
        facts: dict[str, Any],
        has_uses: bool,
        has_side_effects: bool,
        has_warnings: bool,
        has_class: bool,
        uses_raw: Optional[str],
        side_effects_raw: Optional[str],
        warnings_raw: Optional[str],
        class_raw: Optional[str],
        composition: Optional[str],
        active: Optional[str],
    ) -> dict[str, Any]:
        if not _ai_available():
            return {"ai_used": False}

        # Instruct model: ONLY rephrase keys present; omit/unavailable for missing
        allowed_keys = {
            "what_it_is": True,
            "what_it_is_used_for": bool(has_uses or has_class),
            "how_it_works": bool(has_class or composition),
            "important_information": True,
            "common_side_effects": bool(has_side_effects),
            "warnings": bool(has_warnings),
        }

        system = (
            "You rewrite Australian medicine DATABASE FIELDS into clear patient-friendly "
            "English. You are NOT a source of medical facts. "
            "You MUST use ONLY the JSON fields provided. "
            "You MUST NOT invent indications, dosage, contraindications, interactions, "
            "side effects, warnings, or mechanisms not present in the input. "
            "If a section is marked not_allowed, set its value to exactly: "
            f"{UNAVAILABLE!r}. "
            "Return valid JSON only."
        )
        user = {
            "database_fields_only": facts,
            "section_allowed": allowed_keys,
            "rules": [
                "what_it_is: describe identity from name/form/strength/ingredient only",
                "what_it_is_used_for: only if uses or therapeutic/drug class present; else unavailable string",
                "how_it_works: only high-level from class/composition if present; else unavailable string",
                "common_side_effects: rephrase side_effects field only; else unavailable string",
                "warnings: rephrase warnings field only; else unavailable string",
                "Do not add dosage instructions",
                "Do not add drug interactions",
            ],
            "output_schema": {
                "what_it_is": "string",
                "what_it_is_used_for": "string",
                "how_it_works": "string",
                "important_information": "string",
                "common_side_effects": "string",
                "warnings": "string",
            },
        }

        try:
            client = _new_client()
            ai_log.debug(
                "Medicine explanation rephrase medicine_id=%s keys=%s",
                facts.get("medicine_id"),
                list(facts.keys()),
            )
            response = await client.messages.create(
                model=_MODEL_HAIKU,
                max_tokens=900,
                system=system,
                messages=[
                    {
                        "role": "user",
                        "content": json.dumps(user, default=str),
                    }
                ],
            )
            text = response.content[0].text
            m = re.search(r"\{.*\}", text, re.DOTALL)
            if not m:
                return {"ai_used": False}
            parsed = json.loads(m.group())
            # Hard filter: drop AI content for disallowed sections
            out: dict[str, Any] = {"ai_used": True}
            for key, allowed in allowed_keys.items():
                val = parsed.get(key)
                if not allowed:
                    continue
                if not _nonempty(val) or str(val).strip() == UNAVAILABLE:
                    continue
                # Reject obvious invention markers for clinical sections
                if key in ("common_side_effects", "warnings", "what_it_is_used_for", "how_it_works"):
                    if key == "common_side_effects" and not has_side_effects:
                        continue
                    if key == "warnings" and not has_warnings:
                        continue
                    if key == "what_it_is_used_for" and not (has_uses or has_class):
                        continue
                    if key == "how_it_works" and not (has_class or composition):
                        continue
                out[key] = str(val).strip()
            return out
        except Exception as e:
            ai_log.error("Medicine explanation AI failed: %s: %s", type(e).__name__, e)
            return {"ai_used": False}

    @staticmethod
    def _fallback_what_it_is(facts: dict) -> str:
        parts = [facts.get("name") or "This medicine"]
        if facts.get("generic_name"):
            parts.append(f"(generic name: {facts['generic_name']})")
        if facts.get("active_ingredient"):
            parts.append(f"contains {facts['active_ingredient']}")
        if facts.get("strength"):
            parts.append(f"at a strength of {facts['strength']}")
        form = facts.get("dosage_form") or facts.get("dosage_forms")
        if form:
            parts.append(f"as {form}")
        return " ".join(str(p) for p in parts) + "."

    @staticmethod
    def _fallback_used_for(uses: Optional[str], class_raw: Optional[str]) -> str:
        if uses:
            return str(uses)
        if class_raw:
            return (
                f"Listed therapeutic/drug class in the dataset: {class_raw}. "
                "Specific approved uses are not fully described in the current record."
            )
        return UNAVAILABLE

    @staticmethod
    def _fallback_how_it_works(class_raw: Optional[str], composition: Optional[str]) -> str:
        bits = []
        if class_raw:
            bits.append(f"Classified in this dataset as: {class_raw}.")
        if composition:
            bits.append(f"Composition on record: {composition}.")
        return " ".join(bits) if bits else UNAVAILABLE

    @staticmethod
    def _fallback_important(facts: dict, tga_pbs: dict) -> str:
        bits = []
        if tga_pbs.get("tga_artg_number"):
            bits.append(f"TGA ARTG: {tga_pbs['tga_artg_number']}.")
        if tga_pbs.get("pbs_code"):
            bits.append(f"PBS code: {tga_pbs['pbs_code']}.")
        if tga_pbs.get("schedule"):
            bits.append(f"Schedule: {tga_pbs['schedule']}.")
        if tga_pbs.get("sponsor"):
            bits.append(f"Sponsor/manufacturer: {tga_pbs['sponsor']}.")
        if tga_pbs.get("data_source"):
            bits.append(f"Catalog provenance: {tga_pbs['data_source']}.")
        bits.append(
            "Always follow the directions on your prescription or pack, "
            "and ask a pharmacist or doctor if unsure."
        )
        return " ".join(bits)
