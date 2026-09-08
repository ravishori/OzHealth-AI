"""
Health Insights — HN-FUTURE-003 (grounded)

GET  /api/v1/insights/summary              — grounded personal insights
GET  /api/v1/insights/alerts               — grounded (compat shape)
GET  /api/v1/insights/consultation-advice  — grounded consultation context
POST /api/v1/insights/translate            — existing translate helper

Personal insights are derived from authenticated-user HealthNest data only.
"""
from __future__ import annotations

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.log_decorator import LoggedAPIRoute
from app.models.family_member import FamilyMember
from app.models.user import User
from app.services.ai_service import translate_health_info
from app.services.health_insights_service import (
    INSIGHTS_DISCLAIMER,
    build_grounded_insights_payload,
)

router = APIRouter(route_class=LoggedAPIRoute)
logger = logging.getLogger(__name__)


async def _require_owned_active_family_member(
    db: AsyncSession,
    family_member_id: int,
    user_id: int,
) -> FamilyMember:
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


async def _resolve_subject(
    db: AsyncSession,
    current_user: User,
    family_member_id: Optional[int],
) -> Optional[int]:
    if family_member_id is None:
        return None
    await _require_owned_active_family_member(
        db, family_member_id, current_user.id
    )
    return family_member_id


@router.get("/summary")
async def get_insights_summary(
    period_days: int = Query(30, ge=1, le=365),
    family_member_id: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Grounded health insights from the authenticated user's recorded data."""
    subject_fm = await _resolve_subject(db, current_user, family_member_id)
    payload = await build_grounded_insights_payload(
        db,
        current_user,
        period_days=period_days,
        family_member_id=subject_fm,
        use_ai_explain=True,
    )
    return payload


@router.get("/alerts")
async def get_predictive_alerts(
    period_days: int = Query(30, ge=1, le=365),
    family_member_id: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Grounded insights in a backward-compatible alerts envelope.

    Previously AI-invented predictive alerts; now data-grounded only.
    """
    subject_fm = await _resolve_subject(db, current_user, family_member_id)
    return await build_grounded_insights_payload(
        db,
        current_user,
        period_days=period_days,
        family_member_id=subject_fm,
        use_ai_explain=True,
    )


@router.get("/consultation-advice")
async def get_consultation_advice(
    period_days: int = Query(30, ge=1, le=365),
    family_member_id: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Non-diagnostic consultation guidance derived from grounded insight facts.

    Does not diagnose or prescribe. Encourages professional review when data
    shows incomplete monitoring or user-confirmed lab extractions exist.
    """
    subject_fm = await _resolve_subject(db, current_user, family_member_id)
    grounded = await build_grounded_insights_payload(
        db,
        current_user,
        period_days=period_days,
        family_member_id=subject_fm,
        use_ai_explain=False,
    )

    reasons: list[str] = []
    actions: list[str] = [
        "Review your recorded HealthNest data with a GP or pharmacist when concerned.",
        "Call 000 in a medical emergency — HealthNest does not contact emergency services.",
    ]

    avail = grounded.get("data_availability") or {}
    if (avail.get("metrics_count") or 0) == 0:
        reasons.append("No recent health measurements are recorded yet.")
        actions.insert(
            0, "Log a few vitals so future insights can summarise your own trends."
        )
    else:
        reasons.append(
            f"{avail.get('metrics_count')} recent measurement(s) are available "
            "for discussion with your clinician."
        )

    if avail.get("adherence_source_available") and (avail.get("dose_events_count") or 0) > 0:
        reasons.append(
            "Medication dose history is available as a record summary "
            "(not a compliance judgment)."
        )
    elif not avail.get("adherence_source_available"):
        reasons.append(
            "Medication dose-history insights are not available in this environment."
        )

    lab_insight = next(
        (i for i in grounded.get("insights") or [] if i.get("category") == "lab"),
        None,
    )
    if lab_insight and lab_insight.get("status") == "grounded":
        reasons.append(
            "User-confirmed lab extractions exist in your records "
            "(informational — not clinician verified)."
        )
    elif lab_insight and (lab_insight.get("facts") or {}).get("unreviewed_count"):
        reasons.append(
            "Unreviewed lab extractions were excluded from authoritative insights."
        )

    urgency = "routine"
    consult_needed = True  # conservative: always OK to discuss with GP
    advice = (
        "Based only on data recorded in HealthNest, consider discussing your "
        "recorded measurements and medication history with a GP when you have "
        "questions. This is not a diagnosis and does not replace clinical judgment."
    )

    return {
        "consult_needed": consult_needed,
        "urgency": urgency,
        "urgency_label": "Routine discussion with a GP as needed",
        "advice": advice,
        "recommendation": advice,
        "reasons": reasons,
        "next_steps": actions,
        "actions": actions,
        "suggested_specialist": "GP",
        "disclaimer": INSIGHTS_DISCLAIMER,
        "is_diagnosis": False,
        "guidance_type": "informational",
        "grounded_from": {
            "period_days": period_days,
            "data_availability": avail,
        },
    }


class TranslateRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=5000)
    language: str  # "hindi" or "marathi"


@router.post("/translate")
async def translate_to_regional_language(
    req: TranslateRequest,
    current_user: User = Depends(get_current_user),
):
    """Translate health information to Hindi or Marathi — Feature #11 & #27."""
    # Metadata only — do not log translation body (may contain health text).
    logger.info(
        "insights_translate user_id=%s lang=%s text_len=%d",
        current_user.id,
        req.language,
        len(req.text or ""),
    )
    translated = await translate_health_info(req.text, req.language)
    return {
        "original": req.text,
        "translated": translated,
        "language": req.language,
    }
