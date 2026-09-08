"""HN-MEDMGMT-006 — medication dose history schemas."""
from datetime import datetime
from typing import Optional, Literal

from pydantic import BaseModel, field_validator


ALLOWED_DOSE_STATUSES = frozenset({"taken", "skipped", "missed"})
DoseStatus = Literal["taken", "skipped", "missed"]


def normalize_dose_status(value: str) -> str:
    key = (value or "").strip().lower()
    if key not in ALLOWED_DOSE_STATUSES:
        raise ValueError(
            f"Invalid status '{value}'. Allowed: {sorted(ALLOWED_DOSE_STATUSES)}"
        )
    return key


class MedicationDoseEventCreate(BaseModel):
    """Record a dose occurrence. Ownership is never client-supplied."""

    medication_schedule_id: int
    status: str
    # Identifies the scheduled occurrence (date+time). Distinct from recorded_at.
    scheduled_for: datetime

    @field_validator("status")
    @classmethod
    def _normalize_status(cls, v: str) -> str:
        return normalize_dose_status(v)


class MedicationDoseEventResponse(BaseModel):
    id: int
    medication_schedule_id: int
    family_member_id: Optional[int] = None
    medicine_name: Optional[str] = None
    dosage: Optional[str] = None
    status: str
    scheduled_for: datetime
    recorded_at: datetime
    created_at: datetime
    # True when an identical (schedule, scheduled_for) submit returned the
    # existing row instead of inserting a duplicate (idempotent retry).
    duplicate: bool = False

    class Config:
        from_attributes = True


class MedicationAdherenceSummary(BaseModel):
    taken: int
    skipped: int
    missed: int
    total: int
    # taken / total * 100 when total > 0; else null
    adherence_percent: Optional[float] = None
