"""
FastAPI routes for the medicine caching layer.

Three endpoints:
    GET  /api/medicine/search       — primary search; never bypasses the cache
    POST /api/cache/refresh         — operator/worker-triggered refresh
    GET  /api/medicine/popular      — analytics; top medicines by popularity
    GET  /api/medicine/cache/stats  — bonus ops endpoint

All endpoints are async, all use the AsyncSession dependency, all return
Pydantic-validated payloads.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.log_decorator import LoggedAPIRoute
from app.models.user import User
from app.schemas.medicine_cache import (
    CacheRefreshRequest,
    CacheRefreshResponse,
    MedicineSearchResponse,
    PopularMedicine,
    PopularMedicinesResponse,
)
from app.services.medicine_analytics_service import MedicineAnalyticsService
from app.services.medicine_search_service import MedicineSearchService

router = APIRouter(route_class=LoggedAPIRoute)


# ─── Search ───────────────────────────────────────────────────────────────────
@router.get(
    "/medicine/search",
    response_model=MedicineSearchResponse,
    summary="Search medicines (cache-first, AI-fallback)",
)
async def medicine_search(
    q: str = Query(..., min_length=2, description="Free-text medicine query"),
    db:           AsyncSession = Depends(get_db),
    current_user: User         = Depends(get_current_user),
) -> MedicineSearchResponse:
    service = MedicineSearchService(db)
    result  = await service.search(q)
    return MedicineSearchResponse(**result)


# ─── Cache refresh ────────────────────────────────────────────────────────────
@router.post(
    "/cache/refresh",
    response_model=CacheRefreshResponse,
    summary="Refresh a specific medicine cache entry (ops + workers)",
)
async def refresh_cache(
    body: CacheRefreshRequest,
    db:           AsyncSession = Depends(get_db),
    current_user: User         = Depends(get_current_user),
) -> CacheRefreshResponse:
    service = MedicineSearchService(db)
    result  = await service.refresh(body.query, force=body.force)
    return CacheRefreshResponse(**result)


# ─── Analytics ────────────────────────────────────────────────────────────────
@router.get(
    "/medicine/popular",
    response_model=PopularMedicinesResponse,
    summary="Top medicines by popularity score",
)
async def popular_medicines(
    limit:  int = Query(50, ge=1, le=200),
    offset: int = Query(0,  ge=0),
    db:           AsyncSession = Depends(get_db),
    current_user: User         = Depends(get_current_user),
) -> PopularMedicinesResponse:
    svc = MedicineAnalyticsService(db)
    rows = await svc.popular_medicines(limit=limit, offset=offset)
    items = [
        PopularMedicine(
            medicine_id      = r.id,
            name             = r.name,
            generic_name     = r.generic_name,
            search_count     = r.search_count or 0,
            cache_hit_count  = r.cache_hit_count or 0,
            ai_hit_count     = r.ai_hit_count or 0,
            popular_score    = float(r.popular_score or 0.0),
            last_searched_at = r.last_searched_at,
        )
        for r in rows
    ]
    return PopularMedicinesResponse(items=items, total=len(items))


@router.get(
    "/medicine/cache/stats",
    summary="Cache + enrichment metrics (ops dashboard)",
)
async def cache_stats(
    db:           AsyncSession = Depends(get_db),
    current_user: User         = Depends(get_current_user),
):
    svc = MedicineAnalyticsService(db)
    return await svc.cache_overview()
