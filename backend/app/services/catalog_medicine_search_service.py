"""
Catalog medicine search — MigrationTest AU medicines.

Uses existing PostgreSQL btree / trigram / ARTG / PBS indexes.
No vector search, Elasticsearch, AI enrichment, or schema changes.
"""
from __future__ import annotations

import json
import logging
import re
import time
from typing import Any, Optional

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.medicine import Medicine
from app.models.medicine_search_models import MedicineIngredientStrength, PbsListing

logger = logging.getLogger(__name__)

MAX_QUERY_LEN = 100
DEFAULT_LIMIT = 20
MAX_LIMIT = 50

_PBS_RE = re.compile(r"^[0-9]{1,5}[A-Z]$", re.IGNORECASE)
_ARTG_RE = re.compile(r"^(?:ARTG[-\s]?)?(\d{4,8})$", re.IGNORECASE)


def validate_search_query(q: str) -> str:
    q = (q or "").strip()
    if len(q) < 1:
        raise ValueError("Query must not be empty")
    if len(q) > MAX_QUERY_LEN:
        raise ValueError(f"Query exceeds maximum length of {MAX_QUERY_LEN}")
    # Block trivial control / injection noise (parameterised SQL still used)
    if "\x00" in q:
        raise ValueError("Invalid query characters")
    return q


def clamp_limit(limit: Optional[int]) -> int:
    if limit is None:
        return DEFAULT_LIMIT
    return max(1, min(int(limit), MAX_LIMIT))


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


class CatalogMedicineSearchService:
    """Minimum AU medicine catalog search over medicines + ingredients + PBS."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def search(self, query: str, *, limit: int = DEFAULT_LIMIT) -> dict[str, Any]:
        q = validate_search_query(query)
        lim = clamp_limit(limit)
        t0 = time.perf_counter()

        ids = await self._find_ids(q, lim)
        if not ids:
            ms = round((time.perf_counter() - t0) * 1000, 1)
            return {
                "query": q,
                "count": 0,
                "limit": lim,
                "elapsed_ms": ms,
                "source": "database",
                "results": [],
            }

        medicines = await self._load_medicines(ids)
        ingredients = await self._load_ingredients(ids)
        listings = await self._load_pbs_listings(ids)

        # Preserve rank order from id list; drop duplicates
        by_id = {m.id: m for m in medicines}
        results = []
        seen: set[int] = set()
        for mid in ids:
            if mid in seen or mid not in by_id:
                continue
            seen.add(mid)
            results.append(
                self._to_result(
                    by_id[mid],
                    ingredients.get(mid, []),
                    listings.get(mid, []),
                )
            )

        ms = round((time.perf_counter() - t0) * 1000, 1)
        return {
            "query": q,
            "count": len(results),
            "limit": lim,
            "elapsed_ms": ms,
            "source": "database",
            "results": results,
        }

    async def _find_ids(self, q: str, limit: int) -> list[int]:
        qlow = q.lower()
        pbs_exact = q.upper() if _PBS_RE.match(q) else None
        artg_m = _ARTG_RE.match(q.replace(" ", ""))
        artg_digits = artg_m.group(1) if artg_m else None
        artg_pref = f"ARTG-{artg_digits}" if artg_digits else None

        # Ranked search using existing indexes (name_trgm, generic_trgm, artg, pbs, ingredient)
        sql = text(
            """
            WITH params AS (
                SELECT
                    :qlow AS qlow,
                    :prefix AS prefix,
                    :partial AS partial,
                    :pbs AS pbs,
                    :artg AS artg,
                    :artg_digits AS artg_digits
            )
            SELECT id, rank_score
            FROM (
                SELECT
                    m.id,
                    CASE
                        WHEN :pbs IS NOT NULL AND upper(btrim(m.pbs_code)) = :pbs THEN 10
                        WHEN :artg IS NOT NULL AND (
                            upper(btrim(m.tga_artg_number)) = upper(:artg)
                            OR btrim(m.tga_artg_number) = :artg_digits
                        ) THEN 9
                        WHEN lower(m.name) = :qlow THEN 8
                        WHEN lower(m.generic_name) = :qlow THEN 7
                        WHEN lower(m.brand_name) = :qlow THEN 7
                        WHEN lower(m.canonical_key) = :qlow THEN 6
                        WHEN lower(m.normalized_name) = :qlow THEN 6
                        WHEN lower(m.name) LIKE :prefix THEN 5
                        WHEN lower(COALESCE(m.generic_name, '')) LIKE :prefix THEN 5
                        WHEN lower(COALESCE(m.brand_name, '')) LIKE :prefix THEN 5
                        WHEN lower(COALESCE(m.active_ingredient, '')) LIKE :partial THEN 4
                        WHEN EXISTS (
                            SELECT 1 FROM medicine_ingredient_strengths i
                            WHERE i.medicine_id = m.id
                              AND lower(i.ingredient_name) LIKE :partial
                        ) THEN 4
                        WHEN lower(m.name) LIKE :partial THEN 3
                        WHEN lower(COALESCE(m.generic_name, '')) LIKE :partial THEN 3
                        WHEN lower(COALESCE(m.brand_name, '')) LIKE :partial THEN 3
                        WHEN lower(COALESCE(m.normalized_name, '')) LIKE :partial THEN 3
                        WHEN m.tga_artg_number ILIKE :partial THEN 3
                        WHEN m.pbs_code ILIKE :partial THEN 3
                        ELSE 1
                    END AS rank_score
                FROM medicines m, params
                WHERE
                    (:pbs IS NOT NULL AND upper(btrim(m.pbs_code)) = :pbs)
                    OR (
                        :artg IS NOT NULL AND (
                            upper(btrim(m.tga_artg_number)) = upper(:artg)
                            OR btrim(m.tga_artg_number) = :artg_digits
                        )
                    )
                    OR lower(m.name) = :qlow
                    OR lower(COALESCE(m.generic_name, '')) = :qlow
                    OR lower(COALESCE(m.brand_name, '')) = :qlow
                    OR lower(COALESCE(m.canonical_key, '')) = :qlow
                    OR lower(COALESCE(m.normalized_name, '')) = :qlow
                    OR lower(m.name) LIKE :prefix
                    OR lower(COALESCE(m.generic_name, '')) LIKE :prefix
                    OR lower(COALESCE(m.brand_name, '')) LIKE :prefix
                    OR lower(COALESCE(m.active_ingredient, '')) LIKE :partial
                    OR lower(m.name) LIKE :partial
                    OR lower(COALESCE(m.generic_name, '')) LIKE :partial
                    OR lower(COALESCE(m.brand_name, '')) LIKE :partial
                    OR lower(COALESCE(m.normalized_name, '')) LIKE :partial
                    OR m.tga_artg_number ILIKE :partial
                    OR m.pbs_code ILIKE :partial
                    OR EXISTS (
                        SELECT 1 FROM medicine_ingredient_strengths i
                        WHERE i.medicine_id = m.id
                          AND lower(i.ingredient_name) LIKE :partial
                    )
            ) ranked
            ORDER BY rank_score DESC, id ASC
            LIMIT :lim
            """
        )
        params = {
            "qlow": qlow,
            "prefix": f"{qlow}%",
            "partial": f"%{qlow}%",
            "pbs": pbs_exact,
            "artg": artg_pref,
            "artg_digits": artg_digits,
            "lim": limit,
        }
        result = await self.db.execute(sql, params)
        rows = result.fetchall()
        # Deduplicate while preserving order
        out: list[int] = []
        seen: set[int] = set()
        for r in rows:
            mid = int(r[0])
            if mid not in seen:
                seen.add(mid)
                out.append(mid)
        return out

    async def _load_medicines(self, ids: list[int]) -> list[Medicine]:
        stmt = select(Medicine).where(Medicine.id.in_(ids))
        return list((await self.db.execute(stmt)).scalars().all())

    async def _load_ingredients(self, ids: list[int]) -> dict[int, list[dict]]:
        stmt = (
            select(MedicineIngredientStrength)
            .where(MedicineIngredientStrength.medicine_id.in_(ids))
            .order_by(
                MedicineIngredientStrength.medicine_id,
                MedicineIngredientStrength.position,
                MedicineIngredientStrength.ingredient_strength_id,
            )
        )
        rows = list((await self.db.execute(stmt)).scalars().all())
        out: dict[int, list[dict]] = {}
        for r in rows:
            out.setdefault(r.medicine_id, []).append(
                {
                    "name": r.ingredient_name,
                    "role": r.ingredient_role,
                    "strength_value": float(r.strength_value)
                    if r.strength_value is not None
                    else None,
                    "strength_unit": r.strength_unit,
                    "source": r.source,
                }
            )
        return out

    async def _load_pbs_listings(self, ids: list[int]) -> dict[int, list[dict]]:
        stmt = select(PbsListing).where(PbsListing.medicine_id.in_(ids))
        rows = list((await self.db.execute(stmt)).scalars().all())
        out: dict[int, list[dict]] = {}
        for r in rows:
            if r.medicine_id is None:
                continue
            out.setdefault(r.medicine_id, []).append(
                {
                    "pbs_code": r.pbs_code,
                    "program_code": r.program_code,
                    "restriction_level": r.restriction_level,
                    "authority_required": r.authority_required,
                    "max_quantity": r.max_quantity,
                    "repeats_allowed": r.repeats_allowed,
                    "effective_date": r.effective_date.isoformat()
                    if r.effective_date
                    else None,
                    "is_active": r.is_active,
                }
            )
        return out

    def _to_result(
        self,
        m: Medicine,
        ingredients: list[dict],
        pbs_listings: list[dict],
    ) -> dict[str, Any]:
        brand = m.brand_name
        if not brand:
            brands = _parse_jsonish(m.brand_names)
            if isinstance(brands, list) and brands:
                brand = brands[0] if isinstance(brands[0], str) else str(brands[0])
            elif isinstance(brands, str):
                brand = brands

        dosage_form = m.dosage_form
        if not dosage_form:
            forms = _parse_jsonish(m.dosage_forms)
            if isinstance(forms, list) and forms:
                dosage_form = forms[0] if isinstance(forms[0], str) else str(forms[0])
            elif forms is not None:
                dosage_form = forms

        return {
            "id": m.id,
            "name": m.name,
            "generic_name": m.generic_name,
            "brand_name": brand,
            "artg_number": m.tga_artg_number,
            "pbs_code": m.pbs_code,
            "strength": m.strength,
            "dosage_form": dosage_form,
            "release_type": getattr(m, "release_type", None),
            "coating_type": getattr(m, "coating_type", None),
            "route": m.route,
            "sponsor": m.sponsor or m.manufacturer,
            "ingredients": ingredients,
            "pbs_listing": pbs_listings[0] if pbs_listings else None,
            "pbs_listings": pbs_listings,
            "provenance": {
                "data_source": m.data_source,
                "primary_source": getattr(m, "primary_source", None),
                "tga_registered": m.tga_registered,
                "registration_status": m.registration_status,
                "pbs_listing_date": m.pbs_listing_date.isoformat()
                if getattr(m, "pbs_listing_date", None)
                else None,
                "canonical_key": getattr(m, "canonical_key", None),
            },
            # Flutter compatibility aliases
            "tga_registered": m.tga_registered,
            "au_schedule": m.schedule,
            "manufacturer": m.manufacturer or m.sponsor,
        }
