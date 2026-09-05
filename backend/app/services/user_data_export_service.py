"""HN-LEGAL-007 — authenticated owner-scoped user data export (APP access).

Builds a JSON-serialisable snapshot of data owned by a single user_id.
Never accepts a client-supplied user id; callers must pass current_user.id.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.ai_conversation import AIConversation
from app.models.emergency_contact import EmergencyContact
from app.models.eprescription import EPrescription, EPrescriptionRefillReminder
from app.models.family_member import FamilyMember
from app.models.health_metric import HealthMetric
from app.models.medical_record import MedicalRecord
from app.models.medication_schedule import MedicationSchedule
from app.models.prescription import Prescription
from app.models.user import User

EXPORT_SCHEMA_VERSION = "1.0"


def _parse_jsonish(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, (list, dict)):
        return value
    if isinstance(value, str):
        try:
            return json.loads(value)
        except (json.JSONDecodeError, TypeError):
            return value
    return value


def _iso(value: Any) -> Any:
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


def profile_for_export(user: User) -> dict[str, Any]:
    """Public profile fields only — no tokens, keys, or internal auth state."""
    return {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "phone": user.phone,
        "phone2": getattr(user, "phone2", None),
        "age": user.age,
        "gender": user.gender,
        "blood_group": user.blood_group,
        "health_conditions": _parse_jsonish(user.health_conditions) or [],
        "allergies": _parse_jsonish(user.allergies) or [],
        "lifestyle_preferences": _parse_jsonish(
            getattr(user, "lifestyle_preferences", None)
        ),
        "suburb": user.suburb,
        "city": user.city,
        "state": user.state,
        "postcode": user.postcode,
        "profile_image_url": user.profile_image_url,
        "is_verified": user.is_verified,
        "created_at": _iso(user.created_at),
    }


def _prescription_row(p: Prescription) -> dict[str, Any]:
    return {
        "id": p.id,
        "family_member_id": p.family_member_id,
        "doctor_name": p.doctor_name,
        "hospital": p.hospital,
        "prescription_date": _iso(p.prescription_date),
        "extracted_medicines": _parse_jsonish(p.extracted_medicines),
        "ai_summary": p.ai_summary,
        "created_at": _iso(p.created_at),
        # raw_ocr_text omitted from default export metadata surface to keep
        # the package focused; medicines + summary cover clinical content.
    }


def _record_row(r: MedicalRecord) -> dict[str, Any]:
    return {
        "id": r.id,
        "family_member_id": r.family_member_id,
        "record_type": r.record_type,
        "title": r.title,
        "file_name": r.file_name,
        "file_type": r.file_type,
        "file_size": getattr(r, "file_size", None),
        "notes": r.notes,
        "record_date": _iso(r.record_date),
        "is_active": r.is_active,
        "created_at": _iso(r.created_at),
        # Intentionally no file_url / file bytes (metadata-only).
    }


def _reminder_row(s: MedicationSchedule) -> dict[str, Any]:
    return {
        "id": s.id,
        "family_member_id": s.family_member_id,
        "medicine_name": s.medicine_name,
        "dosage": s.dosage,
        "frequency": s.frequency,
        "times": _parse_jsonish(s.times),
        "instructions": s.instructions,
        "start_date": _iso(s.start_date),
        "end_date": _iso(s.end_date),
        "refill_date": _iso(s.refill_date),
        "total_quantity": s.total_quantity,
        "remaining_quantity": s.remaining_quantity,
        "is_active": s.is_active,
        "prescription_id": s.prescription_id,
        "created_at": _iso(s.created_at),
    }


def _family_row(m: FamilyMember) -> dict[str, Any]:
    return {
        "id": m.id,
        "name": m.name,
        "relationship": m.relationship,
        "age": m.age,
        "gender": m.gender,
        "blood_group": m.blood_group,
        "medical_conditions": _parse_jsonish(m.medical_conditions),
        "allergies": _parse_jsonish(m.allergies),
        "notes": m.notes,
        "is_active": m.is_active,
        "created_at": _iso(m.created_at),
    }


def _emergency_row(c: EmergencyContact) -> dict[str, Any]:
    return {
        "id": c.id,
        "name": c.name,
        "phone": c.phone,
        "relationship": c.relationship,
        "is_primary": c.is_primary,
        "created_at": _iso(c.created_at),
    }


def _metric_row(m: HealthMetric) -> dict[str, Any]:
    return {
        "id": m.id,
        "family_member_id": m.family_member_id,
        "metric_type": m.metric_type,
        "value": m.value,
        "value2": m.value2,
        "unit": m.unit,
        "notes": m.notes,
        "recorded_at": _iso(m.recorded_at),
        "created_at": _iso(m.created_at),
    }


def _conversation_row(c: AIConversation) -> dict[str, Any]:
    return {
        "id": c.id,
        "title": c.title,
        "context_type": c.context_type,
        "messages": _parse_jsonish(c.messages),
        "created_at": _iso(c.created_at),
        "updated_at": _iso(c.updated_at),
    }


def _eprescription_row(ep: EPrescription) -> dict[str, Any]:
    return {
        "id": ep.id,
        "provider": ep.provider,
        "status": ep.status,
        "token_last4": ep.token_last4,
        # token_hash intentionally excluded
        "patient_name": ep.patient_name,
        "prescriber_name": ep.prescriber_name,
        "prescriber_provider_number": ep.prescriber_provider_number,
        "prescriber_practice": ep.prescriber_practice,
        "medicines": _parse_jsonish(ep.medicines),
        "prescription_date": _iso(ep.prescription_date),
        "expiry_date": _iso(ep.expiry_date),
        "created_at": _iso(ep.created_at),
    }


async def build_user_data_export(db: AsyncSession, user: User) -> dict[str, Any]:
    """Load all owner-scoped sections for ``user.id`` only."""
    uid = user.id

    rx = await db.execute(
        select(Prescription).where(Prescription.user_id == uid)
    )
    prescriptions = [_prescription_row(p) for p in rx.scalars().all()]

    rec = await db.execute(
        select(MedicalRecord).where(MedicalRecord.user_id == uid)
    )
    records = [_record_row(r) for r in rec.scalars().all()]

    rem = await db.execute(
        select(MedicationSchedule).where(MedicationSchedule.user_id == uid)
    )
    reminders = [_reminder_row(s) for s in rem.scalars().all()]

    fam = await db.execute(
        select(FamilyMember).where(FamilyMember.user_id == uid)
    )
    family_members = [_family_row(m) for m in fam.scalars().all()]

    em = await db.execute(
        select(EmergencyContact).where(EmergencyContact.user_id == uid)
    )
    emergency_contacts = [_emergency_row(c) for c in em.scalars().all()]

    hm = await db.execute(
        select(HealthMetric).where(HealthMetric.user_id == uid)
    )
    health_metrics = [_metric_row(m) for m in hm.scalars().all()]

    ai = await db.execute(
        select(AIConversation).where(AIConversation.user_id == uid)
    )
    ai_conversations = [_conversation_row(c) for c in ai.scalars().all()]

    ep = await db.execute(
        select(EPrescription).where(EPrescription.user_id == uid)
    )
    eprescriptions = [_eprescription_row(e) for e in ep.scalars().all()]

    # Refill reminders only for this user's e-prescriptions
    ep_ids = [e["id"] for e in eprescriptions]
    ep_refills: list[dict[str, Any]] = []
    if ep_ids:
        rr = await db.execute(
            select(EPrescriptionRefillReminder).where(
                EPrescriptionRefillReminder.user_id == uid,
                EPrescriptionRefillReminder.ep_id.in_(ep_ids),
            )
        )
        for row in rr.scalars().all():
            ep_refills.append(
                {
                    "id": row.id,
                    "ep_id": row.ep_id,
                    "medicine_name": row.medicine_name,
                    "refill_date": _iso(row.refill_date),
                    "note": getattr(row, "note", None),
                    "is_notified": getattr(row, "is_notified", None),
                    "created_at": _iso(row.created_at),
                }
            )

    return {
        "export_schema_version": EXPORT_SCHEMA_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "user_id": uid,
        "profile": profile_for_export(user),
        "prescriptions": prescriptions,
        "medical_records": records,
        "reminders": reminders,
        "family_members": family_members,
        "emergency_contacts": emergency_contacts,
        "health_metrics": health_metrics,
        "ai_conversations": ai_conversations,
        "eprescriptions": eprescriptions,
        "eprescription_refill_reminders": ep_refills,
    }


# Keys that must never appear in a serialised export payload
FORBIDDEN_EXPORT_KEYS = frozenset(
    {
        "password",
        "password_hash",
        "hashed_password",
        "access_token",
        "refresh_token",
        "fcm_token",
        "token_version",
        "token_hash",
        "encryption_key",
        "ENCRYPTION_KEY",
        "secret_key",
        "SECRET_KEY",
        "otp",
        "otp_code",
        "otp_hash",
    }
)


def assert_export_has_no_secrets(payload: dict[str, Any]) -> None:
    """Raise AssertionError if forbidden keys appear anywhere in the tree."""

    def _walk(obj: Any, path: str = "") -> None:
        if isinstance(obj, dict):
            for k, v in obj.items():
                key = str(k)
                if key in FORBIDDEN_EXPORT_KEYS or key.lower() in {
                    x.lower() for x in FORBIDDEN_EXPORT_KEYS
                }:
                    raise AssertionError(f"Forbidden key at {path}.{key}")
                _walk(v, f"{path}.{key}")
        elif isinstance(obj, list):
            for i, item in enumerate(obj):
                _walk(item, f"{path}[{i}]")

    _walk(payload)
