"""
Health Insights & Predictive Alerts — Feature #33 (dashboard) + #40 (predictive alerts)
GET /api/v1/insights/alerts
GET /api/v1/insights/consultation-advice
POST /api/v1/insights/translate
"""
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import json

from app.core.log_decorator import LoggedAPIRoute
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.health_metric import HealthMetric
from app.models.medication_schedule import MedicationSchedule
from app.services.ai_service import (
    generate_predictive_health_alerts,
    suggest_doctor_consultation,
    translate_health_info,
)

router = APIRouter(route_class=LoggedAPIRoute)


@router.get("/alerts")
async def get_predictive_alerts(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Generate AI-powered predictive health alerts based on recent metrics."""
    # Get last 30 health metrics
    result = await db.execute(
        select(HealthMetric)
        .where(HealthMetric.user_id == current_user.id)
        .order_by(HealthMetric.recorded_at.desc())
        .limit(30)
    )
    metrics = result.scalars().all()

    # Get active medicines
    meds_result = await db.execute(
        select(MedicationSchedule)
        .where(
            MedicationSchedule.user_id == current_user.id,
            MedicationSchedule.is_active == True,
        )
    )
    medicines = [m.medicine_name for m in meds_result.scalars().all()]

    metrics_data = [
        {
            "type": m.metric_type,
            "value": m.value,
            "unit": m.unit,
            "date": m.recorded_at.isoformat() if m.recorded_at else None,
            "notes": m.notes,
        }
        for m in metrics
    ]

    alerts = await generate_predictive_health_alerts(metrics_data, medicines)
    return alerts


@router.get("/consultation-advice")
async def get_consultation_advice(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get AI advice on whether to see a doctor based on current health context."""
    # Recent metrics
    result = await db.execute(
        select(HealthMetric)
        .where(HealthMetric.user_id == current_user.id)
        .order_by(HealthMetric.recorded_at.desc())
        .limit(10)
    )
    metrics = result.scalars().all()

    meds_result = await db.execute(
        select(MedicationSchedule)
        .where(
            MedicationSchedule.user_id == current_user.id,
            MedicationSchedule.is_active == True,
        )
    )
    medicines = [m.medicine_name for m in meds_result.scalars().all()]

    metrics_summary = {}
    for m in metrics:
        if m.metric_type not in metrics_summary:
            metrics_summary[m.metric_type] = f"{m.value} {m.unit or ''}".strip()

    context = {
        "medicines": medicines,
        "symptoms": [],
        "metrics": metrics_summary,
        "duration": "ongoing",
    }

    advice = await suggest_doctor_consultation(context)
    return advice


class TranslateRequest(BaseModel):
    text: str
    language: str  # "hindi" or "marathi"


@router.post("/translate")
async def translate_to_regional_language(
    req: TranslateRequest,
    current_user: User = Depends(get_current_user),
):
    """Translate health information to Hindi or Marathi — Feature #11 & #27."""
    translated = await translate_health_info(req.text, req.language)
    return {
        "original": req.text,
        "translated": translated,
        "language": req.language,
    }
