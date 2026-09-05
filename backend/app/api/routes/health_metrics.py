from fastapi import APIRouter, Depends, Query
from app.core.log_decorator import LoggedAPIRoute
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
from datetime import datetime, timezone

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.health_metric import HealthMetric
from app.schemas.health_metric import HealthMetricCreate, HealthMetricResponse
from app.services.cache_service import CacheService, HEALTH_SUMMARY_TTL
from app.core.logging_config import audit_log

router = APIRouter(route_class=LoggedAPIRoute)


def _compute_status(metric_type: str, value: float, value2: float | None) -> str:
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


@router.post("/", response_model=HealthMetricResponse)
async def log_metric(
    data: HealthMetricCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
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

    # Invalidate summary cache for this user
    await CacheService.delete(f"metrics:summary:{current_user.id}")

    audit_log.info(
        "health_metric_logged",
        extra={"user_id": current_user.id, "metric_type": data.metric_type},
    )
    return metric


@router.get("/")
async def list_metrics(
    metric_type: Optional[str] = None,
    family_member_id: Optional[int] = None,
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = select(HealthMetric).where(
        HealthMetric.user_id == current_user.id
    ).order_by(HealthMetric.recorded_at.desc()).limit(limit)

    if metric_type:
        query = query.where(HealthMetric.metric_type == metric_type)
    if family_member_id:
        query = query.where(HealthMetric.family_member_id == family_member_id)

    result = await db.execute(query)
    return result.scalars().all()


@router.get("/summary")
async def get_summary(
    family_member_id: Optional[int] = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    cache_key = f"metrics:summary:{current_user.id}"
    if family_member_id:
        cache_key += f":fm{family_member_id}"

    cached = await CacheService.get(cache_key)
    if cached is not None:
        return cached

    summary = {}
    for metric_type in METRIC_UNITS.keys():
        query = select(HealthMetric).where(
            HealthMetric.user_id == current_user.id,
            HealthMetric.metric_type == metric_type,
        ).order_by(HealthMetric.recorded_at.desc()).limit(5)

        if family_member_id:
            query = query.where(HealthMetric.family_member_id == family_member_id)

        result = await db.execute(query)
        records = result.scalars().all()

        if records:
            latest = records[0]
            trend = "stable"
            if len(records) >= 2:
                if latest.value > records[-1].value:
                    trend = "up"
                elif latest.value < records[-1].value:
                    trend = "down"

            summary[metric_type] = {
                "latest_value": latest.value,
                "latest_value2": latest.value2,
                "unit": latest.unit,
                "recorded_at": latest.recorded_at.isoformat() if latest.recorded_at else None,
                "trend": trend,
                "status": _compute_status(metric_type, latest.value, latest.value2),
                "history": [
                    {"value": r.value, "value2": r.value2, "recorded_at": r.recorded_at.isoformat() if r.recorded_at else None}
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
