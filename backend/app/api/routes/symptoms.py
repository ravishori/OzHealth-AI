"""
AI Symptom Checker — Feature #23 / HN-FUTURE-001
POST /api/v1/symptoms/check

Informational guidance only — not a diagnosis. Reuses HN-AI-010 fencing
inside ai_service.check_symptoms / suggest_doctor_consultation.
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
_AI_TIMEOUT_SECONDS = 55

_MAX_SYMPTOMS = 20
_MAX_SYMPTOM_LEN = 200
_MAX_TOTAL_CHARS = 2000
_MAX_DURATION_LEN = 100

# Conservative local hints — escalate when AI unavailable/failed.
# Not a full triage protocol; only avoids false reassurance on obvious red flags.
_EMERGENCY_HINTS = (
    "chest pain",
    "crushing chest",
    "shortness of breath",
    "difficulty breathing",
    "can't breathe",
    "cannot breathe",
    "severe allergic",
    "anaphylaxis",
    "stroke",
    "face drooping",
    "unconscious",
    "suicidal",
    "severe bleeding",
)


class SymptomCheckRequest(BaseModel):
    symptoms: Annotated[list[str], Field(min_length=1, description="List of symptoms")]
    duration: str | None = None
    include_consultation_advice: bool = True

    @field_validator("symptoms")
    @classmethod
    def no_empty_symptoms(cls, v: list[str]) -> list[str]:
        cleaned = [s.strip() for s in v if isinstance(s, str) and s.strip()]
        if not cleaned:
            raise ValueError("At least one non-empty symptom is required")
        if len(cleaned) > _MAX_SYMPTOMS:
            raise ValueError(f"At most {_MAX_SYMPTOMS} symptoms allowed")
        for s in cleaned:
            if len(s) > _MAX_SYMPTOM_LEN:
                raise ValueError(
                    f"Each symptom must be at most {_MAX_SYMPTOM_LEN} characters"
                )
        total = sum(len(s) for s in cleaned)
        if total > _MAX_TOTAL_CHARS:
            raise ValueError(
                f"Combined symptom text must be at most {_MAX_TOTAL_CHARS} characters"
            )
        return cleaned

    @field_validator("duration")
    @classmethod
    def duration_limit(cls, v: str | None) -> str | None:
        if v is None:
            return None
        cleaned = v.strip()
        if not cleaned:
            return None
        if len(cleaned) > _MAX_DURATION_LEN:
            raise ValueError(
                f"Duration must be at most {_MAX_DURATION_LEN} characters"
            )
        return cleaned


def _looks_like_emergency(symptoms: list[str]) -> bool:
    joined = " ".join(s.lower() for s in symptoms)
    return any(hint in joined for hint in _EMERGENCY_HINTS)


def _fallback_triage(symptoms: list[str]) -> dict:
    """
    Safe fallback when the AI call fails or times out.
    Escalates conservatively for obvious emergency hints — never reassures
    that care is unnecessary.
    """
    emergency = _looks_like_emergency(symptoms)
    return {
        "urgency": "emergency" if emergency else "soon",
        "urgency_label": (
            "Seek emergency care now — call 000"
            if emergency
            else "See a GP within a few days"
        ),
        "possible_conditions": [],
        "recommendations": [
            "Automated guidance is temporarily unavailable.",
            (
                "If you may be having a medical emergency, call 000 immediately."
                if emergency
                else "Please consult your GP if symptoms persist or worsen."
            ),
        ],
        "red_flags": (
            [
                "Chest pain, severe breathing difficulty, stroke symptoms, "
                "or other sudden severe symptoms require emergency care."
            ]
            if emergency
            else []
        ),
        "self_care": [] if emergency else ["Rest and stay hydrated."],
        "call_000": emergency,
        "disclaimer": (
            "This is general information only — not a diagnosis. "
            "Always consult a qualified healthcare professional. "
            "In an emergency call 000."
        ),
        "ai_available": False,
    }


@router.post("/check")
async def check_patient_symptoms(
    req: SymptomCheckRequest,
    current_user: User = Depends(get_current_user),
):
    """
    Informational symptom guidance with triage hints.

    Ownership: authenticated user only (no client user_id / owner_id).
    Family subject: not supported on this endpoint (Self only).
    """
    # Metadata-only logging — never log symptom text (HN-SEC-007).
    logger.info(
        "Symptom check requested user_id=%s symptom_count=%d duration_len=%d",
        current_user.id,
        len(req.symptoms),
        len(req.duration or ""),
    )

    user_context: dict = {}
    if current_user.age:
        user_context["age"] = current_user.age
    if current_user.gender:
        user_context["gender"] = current_user.gender
    if current_user.health_conditions:
        try:
            raw = current_user.health_conditions
            conds = json.loads(raw) if isinstance(raw, str) else raw
            if isinstance(conds, list):
                user_context["conditions"] = conds
        except Exception:
            pass

    consult_context = {
        "symptoms": req.symptoms,
        "duration": req.duration or "not specified",
        "metrics": {},
        "medicines": [],
    }

    symptom_task = asyncio.create_task(
        check_symptoms(req.symptoms, user_context, duration=req.duration)
    )

    if req.include_consultation_advice:
        consult_task: asyncio.Task | None = asyncio.create_task(
            suggest_doctor_consultation(consult_context)
        )
        tasks = {symptom_task, consult_task}
    else:
        consult_task = None
        tasks = {symptom_task}

    done, pending = await asyncio.wait(tasks, timeout=_AI_TIMEOUT_SECONDS)

    for t in pending:
        t.cancel()
    if pending:
        await asyncio.gather(*pending, return_exceptions=True)
        # Privacy-safe: counts only — never symptom text.
        logger.error(
            "Symptom checker AI timed out after %ds symptom_count=%d",
            _AI_TIMEOUT_SECONDS,
            len(req.symptoms),
        )

    if symptom_task in pending or symptom_task.exception():
        if symptom_task.exception():
            logger.error(
                "Symptom check AI call failed: %s",
                type(symptom_task.exception()).__name__,
            )
        symptom_result = _fallback_triage(req.symptoms)
    else:
        symptom_result = symptom_task.result()
        # If AI returned a soft-unavailable shape without escalation but
        # local hints suggest emergency, escalate conservatively.
        if (
            isinstance(symptom_result, dict)
            and not symptom_result.get("call_000")
            and symptom_result.get("ai_available") is False
            and _looks_like_emergency(req.symptoms)
        ):
            symptom_result = _fallback_triage(req.symptoms)

    if consult_task is None:
        consult_result = None
    elif consult_task in pending or consult_task.exception():
        if consult_task.exception():
            logger.error(
                "Consultation advice AI call failed: %s",
                type(consult_task.exception()).__name__,
            )
        consult_result = None
    else:
        consult_result = consult_task.result()

    return {
        "symptoms_assessed": req.symptoms,
        "triage": symptom_result,
        "consultation_advice": consult_result,
        # Explicit product framing for clients.
        "guidance_type": "informational",
        "is_diagnosis": False,
    }
