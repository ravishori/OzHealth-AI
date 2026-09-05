"""
AI Symptom Checker — Feature #23
POST /api/v1/symptoms/check
"""
import asyncio
import json
import logging
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, field_validator

from app.core.log_decorator import LoggedAPIRoute
from app.core.deps import get_current_user
from app.models.user import User
from app.services.ai_service import check_symptoms, suggest_doctor_consultation

logger = logging.getLogger(__name__)

router = APIRouter(route_class=LoggedAPIRoute)

# Max time (seconds) allowed for the two concurrent AI calls.
# Prevents the request from hanging if Anthropic API is slow.
_AI_TIMEOUT_SECONDS = 55


class SymptomCheckRequest(BaseModel):
    symptoms: Annotated[list[str], Field(min_length=1, description="List of symptoms")]
    duration: str | None = None          # e.g. "2 days", "1 week"
    include_consultation_advice: bool = True

    @field_validator("symptoms")
    @classmethod
    def no_empty_symptoms(cls, v: list[str]) -> list[str]:
        cleaned = [s.strip() for s in v if s.strip()]
        if not cleaned:
            raise ValueError("At least one non-empty symptom is required")
        return cleaned


@router.post("/check")
async def check_patient_symptoms(
    req: SymptomCheckRequest,
    current_user: User = Depends(get_current_user),
):
    """AI-powered symptom checker with triage guidance."""

    # ── Build user context from profile ───────────────────────────────────────
    # Use `health_conditions` — that is the correct column name on the User model.
    user_context: dict = {}
    if current_user.age:
        user_context["age"] = current_user.age
    if current_user.gender:
        user_context["gender"] = current_user.gender
    if current_user.health_conditions:          # ← was incorrectly `medical_conditions`
        try:
            raw = current_user.health_conditions
            conds = json.loads(raw) if isinstance(raw, str) else raw
            if isinstance(conds, list):
                user_context["conditions"] = conds
        except Exception:
            pass

    # ── Consultation context (passed to the second concurrent AI call) ─────────
    consult_context = {
        "symptoms": req.symptoms,
        "duration": req.duration or "not specified",
        "metrics":  {},
        "medicines": [],
    }

    # ── Run AI calls (with hard timeout so the request never hangs) ────────────
    #
    # IMPORTANT: Do NOT nest asyncio.gather(return_exceptions=True) inside
    # asyncio.wait_for — the `return_exceptions=True` flag changes how
    # CancelledError propagates, causing wait_for's timeout to silently fail
    # in Python ≤ 3.11 and leaving the request hanging until the SDK's own
    # 600 s default fires.  Use asyncio.create_task + asyncio.wait instead.
    #
    symptom_task = asyncio.create_task(check_symptoms(req.symptoms, user_context))

    if req.include_consultation_advice:
        consult_task: asyncio.Task | None = asyncio.create_task(
            suggest_doctor_consultation(consult_context)
        )
        tasks = {symptom_task, consult_task}
    else:
        consult_task = None
        tasks = {symptom_task}

    done, pending = await asyncio.wait(tasks, timeout=_AI_TIMEOUT_SECONDS)

    # Cancel anything that didn't finish within the deadline
    for t in pending:
        t.cancel()
    if pending:
        await asyncio.gather(*pending, return_exceptions=True)
        logger.error(
            "Symptom checker AI timed out after %ds for symptoms: %s",
            _AI_TIMEOUT_SECONDS, req.symptoms,
        )

    # Resolve symptom result
    if symptom_task in pending or symptom_task.exception():
        if symptom_task.exception():
            logger.error("Symptom check AI call failed: %s", symptom_task.exception())
        symptom_result = _fallback_triage(req.symptoms)
    else:
        symptom_result = symptom_task.result()

    # Resolve consultation result
    if consult_task is None:
        consult_result = None
    elif consult_task in pending or consult_task.exception():
        if consult_task.exception():
            logger.error("Consultation advice AI call failed: %s", consult_task.exception())
        consult_result = None
    else:
        consult_result = consult_task.result()

    return {
        "symptoms_assessed": req.symptoms,
        "triage":            symptom_result,
        "consultation_advice": consult_result,
    }


def _fallback_triage(symptoms: list[str]) -> dict:
    """
    Safe fallback when the AI call fails or times out.
    Returns a minimal triage structure that the Flutter client can render.
    """
    return {
        "urgency":          "soon",
        "urgency_label":    "See a GP within a few days",
        "possible_conditions": [],
        "recommendations":  [
            "The AI analysis is temporarily unavailable.",
            "Please consult your GP if symptoms persist or worsen.",
        ],
        "red_flags":        [],
        "self_care":        ["Rest and stay hydrated."],
        "call_000":         False,
        "disclaimer": (
            "Always consult a qualified healthcare professional for diagnosis and treatment. "
            "In an emergency call 000."
        ),
    }
