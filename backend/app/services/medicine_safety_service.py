"""
Minimum medicine safety checker — database facts only.

Detects duplicates, allergy/ingredient conflicts, and medicine–medicine
interactions WITHOUT inventing clinical knowledge or using an LLM.

Interactions:
  1) structured public.interactions rows (preferred)
  2) otherwise UNKNOWN — never infer from names alone
  Optional: if medicines.interactions free-text explicitly mentions the
  other medicine's name/ingredient (whole-token), report as database
  text hit with status KNOWN_FROM_TEXT (still not a structured pair record).

Allergy statuses: MATCH | NO_MATCH | UNKNOWN
UNKNOWN must not be treated as safe.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from itertools import combinations
from typing import Any, Optional

from sqlalchemy import or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.medicine import Medicine
from app.models.medicine_search_models import MedicineIngredientStrength

UNAVAILABLE_INTERACTION = (
    "Interaction information not available in the current dataset."
)

_DISCLAIMER = (
    "This medicine safety checker is an information/safety support feature only. "
    "It is not a substitute for a pharmacist or doctor. "
    "It does not provide treatment changes and must not be used to stop or "
    "change medicines without professional advice. "
    "UNKNOWN allergy or interaction results must not be treated as safe."
)


def _norm(s: Optional[str]) -> str:
    if not s:
        return ""
    s = s.lower().strip()
    s = re.sub(r"[®™©]", "", s)
    s = re.sub(r"[^a-z0-9\s/+.-]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _tokens(s: str) -> set[str]:
    n = _norm(s)
    return {t for t in re.split(r"[\s/,;+]+", n) if len(t) >= 3}


@dataclass
class MedBundle:
    id: int
    name: str
    generic_name: Optional[str]
    active_ingredient: Optional[str]
    canonical_key: Optional[str]
    interactions_text: Optional[str]
    ingredients: list[dict[str, Any]]

    @property
    def ingredient_names(self) -> list[str]:
        names = [i["name"] for i in self.ingredients if i.get("name")]
        if self.active_ingredient:
            # split multi-ingredient active field
            for part in re.split(r"[;,+]| and ", self.active_ingredient):
                p = part.strip()
                if p:
                    names.append(p)
        # dedupe normalized
        out: list[str] = []
        seen: set[str] = set()
        for n in names:
            k = _norm(n)
            if k and k not in seen:
                seen.add(k)
                out.append(n)
        return out


class MedicineSafetyChecker:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def check(
        self,
        medicine_ids: list[int],
        *,
        allergies: Optional[list[str]] = None,
    ) -> dict[str, Any]:
        # Deduplicate input ids while preserving order
        seen_ids: set[int] = set()
        ids: list[int] = []
        for mid in medicine_ids:
            if mid not in seen_ids:
                seen_ids.add(mid)
                ids.append(mid)

        if not ids:
            raise ValueError("medicine_ids must not be empty")

        bundles = await self._load_bundles(ids)
        missing = [i for i in ids if i not in bundles]
        if missing:
            raise LookupError(f"Unknown medicine_id(s): {missing}")

        meds = [bundles[i] for i in ids]
        duplicates = self._duplicates(meds)
        allergy_alerts = self._allergies(meds, allergies or [])
        interactions, interaction_stats = await self._interactions(meds)

        # overall_status: informational aggregate — UNKNOWN never means safe
        has_dup = bool(duplicates)
        has_allergy_match = any(a["status"] == "MATCH" for a in allergy_alerts)
        has_allergy_unknown = any(a["status"] == "UNKNOWN" for a in allergy_alerts)
        has_ix_known = any(i["status"] in ("KNOWN", "KNOWN_FROM_TEXT") for i in interactions)
        has_ix_unknown = any(i["status"] == "UNKNOWN" for i in interactions)

        if has_allergy_match or has_dup or has_ix_known:
            overall = "ALERTS_PRESENT"
        elif has_allergy_unknown or has_ix_unknown:
            overall = "INCOMPLETE_DATA"
        else:
            overall = "NO_ALERTS_FROM_AVAILABLE_DATA"

        return {
            "overall_status": overall,
            "medicines": [
                {
                    "medicine_id": m.id,
                    "name": m.name,
                    "generic_name": m.generic_name,
                    "ingredients": m.ingredient_names,
                }
                for m in meds
            ],
            "duplicates": duplicates,
            "allergy_alerts": allergy_alerts,
            "interactions": interactions,
            "data_coverage": {
                "structured_interactions_table_rows": interaction_stats[
                    "structured_rows"
                ],
                "pairs_checked": interaction_stats["pairs"],
                "pairs_known": interaction_stats["known"],
                "pairs_unknown": interaction_stats["unknown"],
                "source": "database",
            },
            "safety": {
                "disclaimer": _DISCLAIMER,
                "unknown_not_safe": True,
                "treatment_advice": False,
            },
        }

    async def _load_bundles(self, ids: list[int]) -> dict[int, MedBundle]:
        stmt = select(Medicine).where(Medicine.id.in_(ids))
        meds = list((await self.db.execute(stmt)).scalars().all())
        ing_stmt = (
            select(MedicineIngredientStrength)
            .where(MedicineIngredientStrength.medicine_id.in_(ids))
            .order_by(
                MedicineIngredientStrength.medicine_id,
                MedicineIngredientStrength.position,
            )
        )
        ings = list((await self.db.execute(ing_stmt)).scalars().all())
        by_med: dict[int, list[dict]] = {}
        for r in ings:
            by_med.setdefault(r.medicine_id, []).append(
                {
                    "name": r.ingredient_name,
                    "role": r.ingredient_role,
                    "source": r.source,
                }
            )

        out: dict[int, MedBundle] = {}
        for m in meds:
            out[m.id] = MedBundle(
                id=m.id,
                name=m.name,
                generic_name=m.generic_name,
                active_ingredient=m.active_ingredient,
                canonical_key=getattr(m, "canonical_key", None),
                interactions_text=m.interactions
                if m.interactions and str(m.interactions).strip()
                else None,
                ingredients=by_med.get(m.id, []),
            )
        return out

    def _duplicates(self, meds: list[MedBundle]) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        for a, b in combinations(meds, 2):
            reasons: list[str] = []
            if a.id == b.id:
                reasons.append("same medicine_id")
            if (
                a.canonical_key
                and b.canonical_key
                and _norm(a.canonical_key) == _norm(b.canonical_key)
            ):
                reasons.append(f"same canonical_key ({a.canonical_key})")

            a_ings = {_norm(x) for x in a.ingredient_names}
            b_ings = {_norm(x) for x in b.ingredient_names}
            shared = sorted(a_ings & b_ings)
            # Also treat containment / primary-token overlap as shared actives
            if not shared:
                soft: set[str] = set()
                for ai in a_ings:
                    for bi in b_ings:
                        if len(ai) >= 4 and len(bi) >= 4 and (ai in bi or bi in ai):
                            soft.add(ai if len(ai) <= len(bi) else bi)
                        at, bt = _tokens(ai), _tokens(bi)
                        inter = {t for t in (at & bt) if len(t) >= 4}
                        soft |= inter
                shared = sorted(soft)
            shared = [s for s in shared if len(s) >= 4]
            if shared:
                reasons.append(
                    "shared active ingredient(s): " + ", ".join(shared)
                )

            # Same normalized generic when both present and equal
            if (
                a.generic_name
                and b.generic_name
                and _norm(a.generic_name) == _norm(b.generic_name)
                and len(_norm(a.generic_name)) >= 4
            ):
                g = _norm(a.generic_name)
                if not any(g in r for r in reasons):
                    reasons.append(f"same generic_name ({a.generic_name})")

            if not reasons:
                continue
            results.append(
                {
                    "medicine_a": {"medicine_id": a.id, "name": a.name},
                    "medicine_b": {"medicine_id": b.id, "name": b.name},
                    "reason": "; ".join(reasons),
                    "source": "database",
                    "status": "DUPLICATE",
                }
            )
        return results

    def _allergies(
        self, meds: list[MedBundle], allergies: list[str]
    ) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        clean_allergies = [a for a in allergies if a and str(a).strip()]
        if not clean_allergies:
            return results

        for med in meds:
            ings = med.ingredient_names
            if not ings:
                for allergy in clean_allergies:
                    results.append(
                        {
                            "medicine": {"medicine_id": med.id, "name": med.name},
                            "ingredient": None,
                            "allergy": allergy,
                            "status": "UNKNOWN",
                            "source": "unavailable",
                            "note": (
                                "No normalized ingredient data for this medicine; "
                                "UNKNOWN must not be treated as safe."
                            ),
                        }
                    )
                continue

            for allergy in clean_allergies:
                an = _norm(allergy)
                atoks = _tokens(allergy)
                matched_ing = None
                for ing in ings:
                    inn = _norm(ing)
                    itoks = _tokens(ing)
                    # MATCH: allergy string contained in ingredient or vice versa,
                    # or significant token overlap (penicillin ↔ amoxicillin is NOT automatic)
                    if an and inn and (an == inn or an in inn or inn in an):
                        matched_ing = ing
                        break
                    # Cross-class: only exact token equality of >=4 char tokens
                    if atoks & itoks:
                        matched_ing = ing
                        break
                if matched_ing:
                    results.append(
                        {
                            "medicine": {"medicine_id": med.id, "name": med.name},
                            "ingredient": matched_ing,
                            "allergy": allergy,
                            "status": "MATCH",
                            "source": "database",
                        }
                    )
                else:
                    results.append(
                        {
                            "medicine": {"medicine_id": med.id, "name": med.name},
                            "ingredient": None,
                            "allergy": allergy,
                            "status": "NO_MATCH",
                            "source": "database",
                        }
                    )
        return results

    async def _interactions(
        self, meds: list[MedBundle]
    ) -> tuple[list[dict[str, Any]], dict[str, int]]:
        results: list[dict[str, Any]] = []
        # Structured table coverage
        row = (
            await self.db.execute(text("SELECT count(*) FROM interactions"))
        ).scalar()
        structured_rows = int(row or 0)

        # Load structured rows for these medicine ids (integer FK)
        ids = [m.id for m in meds]
        structured_by_med: dict[int, list[dict]] = {}
        if structured_rows and ids:
            q = text(
                """
                SELECT id, medicine_id, interacts_with, severity, effect,
                       clinical_effect, source_name, documentation_level
                FROM interactions
                WHERE medicine_id = ANY(:ids)
                """
            )
            # asyncpg wants a list for ANY
            rows = (await self.db.execute(q, {"ids": list(ids)})).mappings().all()
            for r in rows:
                structured_by_med.setdefault(int(r["medicine_id"]), []).append(dict(r))

        known = 0
        unknown = 0
        pairs = 0
        for a, b in combinations(meds, 2):
            pairs += 1
            hit = self._pair_interaction(a, b, structured_by_med)
            if hit["status"] == "UNKNOWN":
                unknown += 1
            else:
                known += 1
            results.append(hit)

        return results, {
            "structured_rows": structured_rows,
            "pairs": pairs,
            "known": known,
            "unknown": unknown,
        }

    def _pair_interaction(
        self,
        a: MedBundle,
        b: MedBundle,
        structured_by_med: dict[int, list[dict]],
    ) -> dict[str, Any]:
        base = {
            "medicine_a": {"medicine_id": a.id, "name": a.name},
            "medicine_b": {"medicine_id": b.id, "name": b.name},
        }

        # 1) Structured interactions table: medicine_id + interacts_with text match
        for left, right in ((a, b), (b, a)):
            labels = [
                _norm(x)
                for x in [right.name, right.generic_name, *right.ingredient_names]
                if x
            ]
            for row in structured_by_med.get(left.id, []):
                iw = _norm(row.get("interacts_with") or "")
                if not iw:
                    continue
                for ln in labels:
                    if len(ln) < 4:
                        continue
                    if iw == ln or iw in ln or ln in iw:
                        return {
                            **base,
                            "severity": row.get("severity") or "unspecified",
                            "description": row.get("clinical_effect")
                            or row.get("effect")
                            or UNAVAILABLE_INTERACTION,
                            "source": "database",
                            "status": "KNOWN",
                            "evidence": {
                                "interaction_id": row.get("id"),
                                "source_name": row.get("source_name"),
                                "documentation_level": row.get(
                                    "documentation_level"
                                ),
                            },
                        }

        # 2) Free-text medicines.interactions field — only when the other
        # medicine's name/ingredient appears as an explicit token/phrase.
        # Never invent; never treat absence as safe.
        for left, right in ((a, b), (b, a)):
            txt = left.interactions_text
            if not txt:
                continue
            tn = _norm(txt)
            for label in [right.name, right.generic_name, *right.ingredient_names]:
                if not label:
                    continue
                ln = _norm(label)
                if len(ln) < 4:
                    continue
                # whole-phrase / token boundary-ish match
                if re.search(rf"(?<![a-z0-9]){re.escape(ln)}(?![a-z0-9])", tn):
                    return {
                        **base,
                        "severity": "unspecified",
                        "description": (
                            f"Catalog free-text interactions field for "
                            f"'{left.name}' mentions '{label}'. "
                            f"Excerpt: {txt[:240]}"
                        ),
                        "source": "database",
                        "status": "KNOWN_FROM_TEXT",
                        "note": (
                            "Derived from medicines.interactions text, not a "
                            "structured pair record in public.interactions."
                        ),
                    }

        return {
            **base,
            "severity": None,
            "description": UNAVAILABLE_INTERACTION,
            "source": "unavailable",
            "status": "UNKNOWN",
        }
