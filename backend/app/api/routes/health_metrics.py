from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.log_decorator import LoggedAPIRoute
from app.core.logging_config import audit_log
from app.models.family_member import FamilyMember
from app.models.health_metric import HealthMetric
from app.models.user import User
from app.schemas.health_metric import HealthMetricCreate, HealthMetricUpdate, HealthMetricResponse
from app.services.cache_service import HEALTH_SUMMARY_TTL, CacheService

router = APIRouter(route_class=LoggedAPIRoute)


def _compute_status(metric_type: str, value: float, value2: float | None) -> str:
    """Band label for recorded values (not a diagnosis). Kept for API compatibility."""
    if metric_type in ("blood_pressure", "blood_pressure_systolic"):
        if value < 90:
            return "low"
        if value < 120:
            return "normal"
        if value < 130:
            return "elevated"
        return "high"
    if metric_type == "blood_sugar":
        if value < 70:
            return "low"
        if value <= 100:
            return "normal"
        if value <= 125:
            return "elevated"
        return "high"
    if metric_type == "heart_rate":
        if value < 60:
            return "low"
        if value <= 100:
            return "normal"
        return "high"
    if metric_type in ("oxygen_saturation", "oxygen_level"):
        if value >= 95:
            return "normal"
        if value >= 90:
            return "low"
        return "critical"
    if metric_type == "temperature":
        if value < 36.0:
            return "low"
        if value <= 37.5:
            return "normal"
        if value <= 38.5:
            return "elevated"
        return "high"
    return "unknown"


METRIC_UNITS = {
    "blood_pressure": "mmHg",
    "blood_pressure_systolic": "mmHg",
    "blood_pressure_diastolic": "mmHg",
    "blood_sugar": "mg/dL",
    "heart_rate": "bpm",
    "oxygen_saturation": "%",
    "oxygen_level": "%",
    "weight": "kg",
    "height": "cm",
    "bmi": "kg/m²",
    "temperature": "°C",
}


async def _require_owned_active_family_member(
    db: AsyncSession,
    family_member_id: int,
    user_id: int,
) -> FamilyMember:
    """404 for missing, inactive, or cross-user members (no existence leak)."""
    result = await db.execute(
        select(FamilyMember).where(
            FamilyMember.id == family_member_id,
            FamilyMember.user_id == user_id,
            FamilyMember.is_active == True,  # noqa: E712
        )
    )
    member = result.scalar_one_or_none()
    if not member:
        raise HTTPException(status_code=404, detail="Family member not found")
    return member


def _days_cutoff(days: Optional[int]) -> Optional[datetime]:
    if days is None:
        return None
    return datetime.now(timezone.utc) - timedelta(days=days)


def _owner_query(user_id: int, family_member_id: Optional[int]):
    query = select(HealthMetric).where(HealthMetric.user_id == user_id)
    if family_member_id is None:
        query = query.where(HealthMetric.family_member_id.is_(None))
    else:
        query = query.where(HealthMetric.family_member_id == family_member_id)
    return query


async def _get_owned_metric(
    db: AsyncSession,
    metric_id: int,
    user_id: int,
) -> HealthMetric:
    """404 for missing or cross-user rows (no existence leak)."""
    result = await db.execute(
        select(HealthMetric).where(
            HealthMetric.id == metric_id,
            HealthMetric.user_id == user_id,
        )
    )
    metric = result.scalar_one_or_none()
    if not metric:
        raise HTTPException(status_code=404, detail="Health metric not found")
    return metric


async def _invalidate_metric_summary(user_id: int) -> None:
    await CacheService.delete(f"metrics:summary:{user_id}")
    await CacheService.invalidate_prefix(f"metrics:summary:{user_id}")


@router.post("/", response_model=HealthMetricResponse)
async def log_metric(
    data: HealthMetricCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if data.family_member_id is not None:
        await _require_owned_active_family_member(
            db, data.family_member_id, current_user.id
        )

    metric = HealthMetric(
        user_id=current_user.id,
        family_member_id=data.family_member_id,
        metric_type=data.metric_type,
        value=data.value,
        value2=data.value2,
        unit=data.unit or METRIC_UNITS.get(data.metric_type),
        notes=data.notes,
        recorded_at=data.recorded_at or datetime.now(timezone.utc),
    )
    db.add(metric)
    await db.commit()
    await db.refresh(metric)

    await _invalidate_metric_summary(current_user.id)

    audit_log.info(
        "health_metric_logged",
        extra={"user_id": current_user.id, "metric_type": data.metric_type},
    )
    return metric


@router.get("/", response_model=List[HealthMetricResponse])
async def list_metrics(
    metric_type: Optional[str] = None,
    family_member_id: Optional[int] = Query(None, ge=1),
    days: Optional[int] = Query(None, ge=1, le=365),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if family_member_id is not None:
        await _require_owned_active_family_member(
            db, family_member_id, current_user.id
        )

    query = _owner_query(current_user.id, family_member_id)
    if metric_type:
        query = query.where(HealthMetric.metric_type == metric_type)
    cutoff = _days_cutoff(days)
    if cutoff is not None:
        query = query.where(HealthMetric.recorded_at >= cutoff)
    query = query.order_by(HealthMetric.recorded_at.desc()).limit(limit)

    result = await db.execute(query)
    return result.scalars().all()


@router.get("/summary")
async def get_summary(
    family_member_id: Optional[int] = Query(None, ge=1),
    days: Optional[int] = Query(None, ge=1, le=365),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if family_member_id is not None:
        await _require_owned_active_family_member(
            db, family_member_id, current_user.id
        )

    cache_key = f"metrics:summary:{current_user.id}"
    if family_member_id:
        cache_key += f":fm{family_member_id}"
    if days:
        cache_key += f":d{days}"

    cached = await CacheService.get(cache_key)
    if cached is not None:
        return cached

    cutoff = _days_cutoff(days)
    summary = {}
    for metric_type in METRIC_UNITS.keys():
        query = _owner_query(current_user.id, family_member_id).where(
            HealthMetric.metric_type == metric_type,
        ).order_by(HealthMetric.recorded_at.desc()).limit(5)
        if cutoff is not None:
            query = query.where(HealthMetric.recorded_at >= cutoff)

        result = await db.execute(query)
        records = result.scalars().all()

        if records:
            latest = records[0]
            trend = "stable"
            if len(records) >= 2:
                oldest = records[-1]
                if latest.value > oldest.value:
                    trend = "up"
                elif latest.value < oldest.value:
                    trend = "down"

            summary[metric_type] = {
                "latest_value": latest.value,
                "latest_value2": latest.value2,
                "unit": latest.unit,
                "recorded_at": latest.recorded_at.isoformat() if latest.recorded_at else None,
                "trend": trend,
                "status": _compute_status(metric_type, latest.value, latest.value2),
                "history": [
                    {
                        "value": r.value,
                        "value2": r.value2,
                        "recorded_at": r.recorded_at.isoformat() if r.recorded_at else None,
                    }
                    for r in records
                ],
            }

    if summary:
        latest_ts = max(
            (v["recorded_at"] for v in summary.values() if v.get("recorded_at")),
            default=None,
        )
        summary["last_updated"] = latest_ts

    await CacheService.set(cache_key, summary, ttl=HEALTH_SUMMARY_TTL)
    return summary


@router.put("/{metric_id}", response_model=HealthMetricResponse)
async def update_metric(
    metric_id: int,
    data: HealthMetricUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    metric = await _get_owned_metric(db, metric_id, current_user.id)

    if metric.metric_type == "blood_pressure" and data.value2 is None:
        raise HTTPException(
            status_code=422,
            detail="blood pressure requires systolic (value) and diastolic (value2)",
        )

    metric.value = data.value
    if data.value2 is not None:
        metric.value2 = data.value2
    if data.unit is not None:
        metric.unit = data.unit
    if "notes" in data.model_fields_set:
        metric.notes = data.notes
    if data.recorded_at is not None:
        metric.recorded_at = data.recorded_at

    await db.commit()
    await db.refresh(metric)
    await _invalidate_metric_summary(current_user.id)

    audit_log.info(
        "health_metric_updated",
        extra={"user_id": current_user.id, "metric_id": metric.id, "metric_type": metric.metric_type},
    )
    return metric


@router.delete("/{metric_id}")
async def delete_metric(
    metric_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    metric = await _get_owned_metric(db, metric_id, current_user.id)
    metric_type = metric.metric_type
    await db.delete(metric)
    await db.commit()
    await _invalidate_metric_summary(current_user.id)

    audit_log.info(
        "health_metric_deleted",
        extra={"user_id": current_user.id, "metric_id": metric_id, "metric_type": metric_type},
    )
    return {"message": "Health metric deleted"}
