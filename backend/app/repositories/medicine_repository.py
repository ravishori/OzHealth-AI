"""
Async repository for the `medicines` table.

All DB access is funnelled through here so services stay readable and we have
exactly one place to tune SQL when search behaviour changes (trigram, full-
text, fuzzy matching, etc.).
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.medicine import Medicine


class MedicineRepository:

    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Reads ────────────────────────────────────────────────────────────────

    async def find_by_normalized(self, normalized: str) -> Optional[Medicine]:
        """
        Best-effort match for a normalised query.
        Tries (in order):
            1. Exact lowercase match on `name`.
            2. Exact lowercase match on `generic_name`.
            3. Prefix match on either.
        """
        n = normalized.strip().lower()
        if not n:
            return None

        # 1+2: exact match
        stmt = (
            select(Medicine)
            .where(
                or_(
                    func.lower(Medicine.name)         == n,
                    func.lower(Medicine.generic_name) == n,
                )
            )
            .limit(1)
        )
        row = (await self.db.execute(stmt)).scalar_one_or_none()
        if row:
            return row

        # 3: prefix
        like = f"{n}%"
        stmt = (
            select(Medicine)
            .where(
                or_(
                    func.lower(Medicine.name).like(like),
                    func.lower(Medicine.generic_name).like(like),
                )
            )
            .order_by(Medicine.popular_score.desc(), Medicine.id.asc())
            .limit(1)
        )
        return (await self.db.execute(stmt)).scalar_one_or_none()

    async def get(self, medicine_id: int) -> Optional[Medicine]:
        return await self.db.get(Medicine, medicine_id)

    async def list_popular(self, *, limit: int = 50, offset: int = 0) -> list[Medicine]:
        stmt = (
            select(Medicine)
            .order_by(Medicine.popular_score.desc(), Medicine.search_count.desc())
            .offset(offset)
            .limit(limit)
        )
        return list((await self.db.execute(stmt)).scalars().all())

    # ── Writes (counters / enrichment flags) ─────────────────────────────────

    async def record_search(self, medicine_id: int, *, cache_hit: bool) -> None:
        """
        Bump search_count + last_searched_at, plus cache_hit_count when this
        was served from cache. Single set-based UPDATE — safe under contention.
        """
        stmt = (
            update(Medicine)
            .where(Medicine.id == medicine_id)
            .values(
                search_count     = Medicine.search_count + 1,
                cache_hit_count  = Medicine.cache_hit_count + (1 if cache_hit else 0),
                last_searched_at = datetime.now(timezone.utc),
                popular_score    = self._popular_score_expr(),
            )
        )
        await self.db.execute(stmt)

    async def record_ai_hit(self, medicine_id: int) -> None:
        await self.db.execute(
            update(Medicine)
            .where(Medicine.id == medicine_id)
            .values(ai_hit_count = Medicine.ai_hit_count + 1)
        )

    async def mark_enriched(self, medicine_id: int, *, cache_version: str) -> None:
        await self.db.execute(
            update(Medicine)
            .where(Medicine.id == medicine_id)
            .values(
                ai_enriched    = True,
                ai_enriched_at = datetime.now(timezone.utc),
                cache_version  = cache_version,
            )
        )

    async def save_enrichment(
        self,
        medicine_id: int,
        *,
        side_effects:        str | None = None,
        interactions:        str | None = None,
        contraindications:   str | None = None,
        warnings:            str | None = None,
        standard_dosage:     str | None = None,
        storage_instructions: str | None = None,
        cache_version:       str,
    ) -> None:
        """
        Merge AI-generated free-text fields into the medicine row, then flip
        ai_enriched=true. Only writes fields the caller actually supplied —
        existing values are preserved.
        """
        patch: dict = {
            "ai_enriched":    True,
            "ai_enriched_at": datetime.now(timezone.utc),
            "cache_version":  cache_version,
        }
        for k, v in {
            "side_effects":         side_effects,
            "interactions":         interactions,
            "contraindications":    contraindications,
            "warnings":             warnings,
            "standard_dosage":      standard_dosage,
            "storage_instructions": storage_instructions,
        }.items():
            if v:
                patch[k] = v

        await self.db.execute(
            update(Medicine).where(Medicine.id == medicine_id).values(**patch)
        )

    async def insert(self, **fields) -> Medicine:
        """Create a fresh medicine row (used when the search finds nothing in the
        local DB and an external source has supplied data)."""
        m = Medicine(**fields)
        self.db.add(m)
        await self.db.flush()
        return m

    # ── Helpers ──────────────────────────────────────────────────────────────

    @staticmethod
    def _popular_score_expr():
        """
        Popularity = exponentially decayed hit rate. Recent + frequent =
        higher score. Used by the worker to decide cache TTL banding and by
        the popular-medicines endpoint for ranking.

        Formula (simple, transparent — tune freely):
            score = search_count + 3 * cache_hit_count - 0.5 * (days_since_last_seen)

        We use SQL expressions so the update stays a single round trip.
        """
        days_since = func.coalesce(
            func.extract(
                "epoch",
                func.now() - func.coalesce(Medicine.last_searched_at, func.now()),
            ) / 86400.0,
            0.0,
        )
        return (
            Medicine.search_count
            + 3 * Medicine.cache_hit_count
            - 0.5 * days_since
        )
