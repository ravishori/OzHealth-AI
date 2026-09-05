"""
Async repository for `medicine_search_cache`.

Cache rows are the canonical "what to return to a search". Hot path:
    1. get_valid(normalized) — one indexed SELECT.
    2. On hit, record_hit() — one indexed UPDATE.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

from sqlalchemy import func, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.medicine_search_cache import MedicineSearchCache


class MedicineCacheRepository:

    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Read ─────────────────────────────────────────────────────────────────

    async def get_valid(self, normalized: str) -> Optional[MedicineSearchCache]:
        """Return cache row iff present AND cache_expiry > now."""
        stmt = (
            select(MedicineSearchCache)
            .where(
                MedicineSearchCache.normalized_query == normalized,
                MedicineSearchCache.cache_expiry > datetime.now(timezone.utc),
            )
            .limit(1)
        )
        return (await self.db.execute(stmt)).scalar_one_or_none()

    async def get_any(self, normalized: str) -> Optional[MedicineSearchCache]:
        """Return cache row regardless of expiry (used by /cache/refresh)."""
        stmt = (
            select(MedicineSearchCache)
            .where(MedicineSearchCache.normalized_query == normalized)
            .limit(1)
        )
        return (await self.db.execute(stmt)).scalar_one_or_none()

    async def list_for_refresh(self, *, limit: int = 100) -> list[MedicineSearchCache]:
        """
        Rows the nightly worker should refresh — popular AND expiring soon,
        OR explicitly flagged needs_refresh.
        """
        soon = datetime.now(timezone.utc) + timedelta(hours=24)
        stmt = (
            select(MedicineSearchCache)
            .where(
                (MedicineSearchCache.needs_refresh.is_(True))
                | (MedicineSearchCache.cache_expiry < soon)
            )
            .order_by(MedicineSearchCache.hit_count.desc())
            .limit(limit)
        )
        return list((await self.db.execute(stmt)).scalars().all())

    # ── Write ────────────────────────────────────────────────────────────────

    async def upsert(
        self,
        *,
        normalized: str,
        query_text: str,
        medicine_id: int | None,
        ai_response: dict,
        prompt_version: str,
        ttl_days: int,
        source_type: str,
        source_priority: int = 100,
    ) -> MedicineSearchCache:
        """
        INSERT … ON CONFLICT (normalized_query) DO UPDATE — atomic upsert. The
        UNIQUE constraint on normalized_query collapses concurrent writers
        from racing lock holders.
        """
        expiry = datetime.now(timezone.utc) + timedelta(days=ttl_days)
        stmt = (
            pg_insert(MedicineSearchCache)
            .values(
                normalized_query = normalized,
                query_text       = query_text,
                medicine_id      = medicine_id,
                ai_response      = ai_response,
                prompt_version   = prompt_version,
                cache_expiry     = expiry,
                source_type      = source_type,
                source_priority  = source_priority,
                hit_count        = 0,
                needs_refresh    = False,
            )
            .on_conflict_do_update(
                index_elements=[MedicineSearchCache.normalized_query],
                set_={
                    "ai_response":     pg_insert(MedicineSearchCache).excluded.ai_response,
                    "prompt_version":  pg_insert(MedicineSearchCache).excluded.prompt_version,
                    "cache_expiry":    pg_insert(MedicineSearchCache).excluded.cache_expiry,
                    "medicine_id":     pg_insert(MedicineSearchCache).excluded.medicine_id,
                    "source_type":     pg_insert(MedicineSearchCache).excluded.source_type,
                    "source_priority": pg_insert(MedicineSearchCache).excluded.source_priority,
                    "needs_refresh":   False,
                },
            )
            .returning(MedicineSearchCache)
        )
        return (await self.db.execute(stmt)).scalar_one()

    async def record_hit(self, cache_id) -> None:
        await self.db.execute(
            update(MedicineSearchCache)
            .where(MedicineSearchCache.cache_id == cache_id)
            .values(
                hit_count   = MedicineSearchCache.hit_count + 1,
                last_hit_at = datetime.now(timezone.utc),
            )
        )

    async def mark_needs_refresh(self, normalized: str) -> None:
        await self.db.execute(
            update(MedicineSearchCache)
            .where(MedicineSearchCache.normalized_query == normalized)
            .values(needs_refresh=True)
        )

    async def count(self) -> int:
        return (await self.db.execute(
            select(func.count()).select_from(MedicineSearchCache)
        )).scalar_one()
