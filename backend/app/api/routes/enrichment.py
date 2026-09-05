"""
HTTP endpoints for the medicine enrichment pipeline.

    POST /api/v1/enrichment/run                — kick off a batch
    POST /api/v1/enrichment/medicine/{id}      — enrich a single medicine
    GET  /api/v1/enrichment/log/{medicine_id}  — last N changes for a medicine
    GET  /api/v1/enrichment/log/recent         — last N changes globally
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.log_decorator import LoggedAPIRoute
from app.models.medicine import Medicine
from app.models.user import User
from app.services.enrichment.log_repository import EnrichmentLogRepository
from app.services.enrichment.orchestrator import MedicineEnrichmentOrchestrator

router = APIRouter(route_class=LoggedAPIRoute)


@router.post("/run", summary="Enrich the next batch of incomplete medicines")
async def run_batch(
    limit: int = Query(50, ge=1, le=500),
    db:           AsyncSession = Depends(get_db),
    current_user: User         = Depends(get_current_user),
):
    orch = MedicineEnrichmentOrchestrator(db)
    report = await orch.enrich_incomplete(limit=limit)
    return report.to_dict()


@router.post("/medicine/{medicine_id}", summary="Enrich a single medicine by id")
async def run_one(
    medicine_id: int,
    db:           AsyncSession = Depends(get_db),
    current_user: User         = Depends(get_current_user),
):
    med = await db.get(Medicine, medicine_id)
    if med is None:
        raise HTTPException(status_code=404, detail="Medicine not found")
    orch   = MedicineEnrichmentOrchestrator(db)
    result = await orch.enrich_one(med)
    return {
        "medicine_id":         result.medicine_id,
        "name":                result.name,
        "run_id":              str(result.run_id),
        "sources_tried":       result.sources_tried,
        "sources_used":        result.sources_used,
        "changed_fields":      result.changed_fields,
        "confidence_score":    result.confidence_score,
        "needs_manual_review": result.needs_manual_review,
        "sql_update":          result.sql_update,
        "cache_key":           result.cache_key,
        "skipped":             result.skipped,
    }


@router.get("/log/recent", summary="Last N enrichment changes (audit feed)")
async def recent_log(
    limit: int = Query(50, ge=1, le=500),
    db:           AsyncSession = Depends(get_db),
    current_user: User         = Depends(get_current_user),
):
    repo = EnrichmentLogRepository(db)
    rows = await repo.recent(limit=limit)
    return [_log_row(r) for r in rows]


@router.get("/log/{medicine_id}", summary="Enrichment history for one medicine")
async def medicine_log(
    medicine_id: int,
    db:           AsyncSession = Depends(get_db),
    current_user: User         = Depends(get_current_user),
):
    repo = EnrichmentLogRepository(db)
    rows = await repo.for_medicine(medicine_id)
    return [_log_row(r) for r in rows]


# ─── helpers ──────────────────────────────────────────────────────────────────
def _log_row(r) -> dict:
    return {
        "log_id":        r.log_id,
        "medicine_id":   r.medicine_id,
        "field_updated": r.field_updated,
        "old_value":     r.old_value,
        "new_value":     r.new_value,
        "source":        r.source,
        "confidence":    float(r.confidence),
        "created_at":    r.created_at,
        "run_id":        str(r.run_id) if r.run_id else None,
    }
