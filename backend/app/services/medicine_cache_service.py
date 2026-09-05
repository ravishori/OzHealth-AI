"""
Read-side cache helpers.

Thin façade over MedicineCacheRepository plus the TTL-banding logic. Keeps
the search service readable.
"""
from __future__ import annotations

import logging
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.medicine import Medicine
from app.models.medicine_search_cache import MedicineSearchCache
from app.repositories.medicine_cache_repository import MedicineCacheRepository

logger = logging.getLogger(__name__)

# TTL banding — the more popular a medicine, the longer we hold its cache.
POPULAR_TTL_DAYS = 90
RARE_TTL_DAYS    = 30
POPULAR_THRESHOLD = 10   # popular_score above this counts as "popular"


class MedicineCacheService:

    def __init__(self, db: AsyncSession):
        self.repo = MedicineCacheRepository(db)

    async def get_valid(self, normalized: str) -> Optional[MedicineSearchCache]:
        return await self.repo.get_valid(normalized)

    async def record_hit(self, cache_id) -> None:
        await self.repo.record_hit(cache_id)

    async def save(
        self,
        *,
        normalized: str,
        query_text: str,
        medicine: Medicine | None,
        ai_response: dict,
        prompt_version: str,
        source_type: str,
        source_priority: int = 100,
    ) -> MedicineSearchCache:
        return await self.repo.upsert(
            normalized      = normalized,
            query_text      = query_text,
            medicine_id     = medicine.id if medicine else None,
            ai_response     = ai_response,
            prompt_version  = prompt_version,
            ttl_days        = self._ttl_for(medicine),
            source_type     = source_type,
            source_priority = source_priority,
        )

    async def mark_needs_refresh(self, normalized: str) -> None:
        await self.repo.mark_needs_refresh(normalized)

    @staticmethod
    def _ttl_for(medicine: Medicine | None) -> int:
        if medicine is None:
            return RARE_TTL_DAYS
        score = float(medicine.popular_score or 0)
        return POPULAR_TTL_DAYS if score >= POPULAR_THRESHOLD else RARE_TTL_DAYS
