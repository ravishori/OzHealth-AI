"""
Read-side analytics for the medicine cache.

Powers /api/medicine/popular and the worker's pick-list. Pure SQL — every
function is a single round trip.
"""
from __future__ import annotations

from typing import Any

from sqlalchemy import Integer, desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.medicine import Medicine
from app.models.medicine_search_cache import MedicineSearchCache


class MedicineAnalyticsService:

    def __init__(self, db: AsyncSession):
        self.db = db

    async def popular_medicines(self, *, limit: int = 50, offset: int = 0) -> list[Medicine]:
        stmt = (
            select(Medicine)
            .where(Medicine.search_count > 0)
            .order_by(
                desc(Medicine.popular_score),
                desc(Medicine.search_count),
            )
            .offset(offset)
            .limit(limit)
        )
        return list((await self.db.execute(stmt)).scalars().all())

    async def cache_overview(self) -> dict[str, Any]:
        """Aggregate metrics for the ops dashboard."""
        # Cache size + hit summary.
        cache_summary = (await self.db.execute(
            select(
                func.count(MedicineSearchCache.cache_id).label("rows"),
                func.coalesce(func.sum(MedicineSearchCache.hit_count), 0).label("total_hits"),
                func.coalesce(func.avg(MedicineSearchCache.hit_count), 0.0).label("avg_hits"),
            )
        )).one()

        # Enrichment progress on the medicine catalog.
        med_summary = (await self.db.execute(
            select(
                func.count(Medicine.id).label("total"),
                func.coalesce(func.sum(
                    func.cast(Medicine.ai_enriched, type_=Integer)
                ), 0).label("enriched"),
                func.coalesce(func.sum(Medicine.search_count), 0).label("total_searches"),
                func.coalesce(func.sum(Medicine.cache_hit_count), 0).label("total_cache_hits"),
                func.coalesce(func.sum(Medicine.ai_hit_count), 0).label("total_ai_hits"),
            )
        )).one()

        total_searches = int(med_summary.total_searches or 0)
        cache_hits     = int(med_summary.total_cache_hits or 0)
        ai_hits        = int(med_summary.total_ai_hits or 0)
        hit_rate = (cache_hits / total_searches * 100.0) if total_searches else 0.0

        return {
            "cache": {
                "rows":        int(cache_summary.rows or 0),
                "total_hits":  int(cache_summary.total_hits or 0),
                "avg_hits":    round(float(cache_summary.avg_hits or 0.0), 2),
            },
            "medicines": {
                "total":             int(med_summary.total or 0),
                "enriched":          int(med_summary.enriched or 0),
                "total_searches":    total_searches,
                "total_cache_hits":  cache_hits,
                "total_ai_hits":     ai_hits,
                "cache_hit_rate_pct": round(hit_rate, 2),
            },
        }
