"""HN-REM-010 — appointment reminder schemas."""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, field_validator

# Allowed local-reminder offsets (minutes before scheduled_at).
ALLOWED_REMIND_BEFORE_MINUTES = frozenset({0, 15, 30, 60, 120, 1440})


def normalize_remind_before_minutes(value: int) -> int:
    if value not in ALLOWED_REMIND_BEFORE_MINUTES:
        raise ValueError(
            f"Invalid remind_before_minutes '{value}'. "
            f"Allowed: {sorted(ALLOWED_REMIND_BEFORE_MINUTES)}"
        )
    return value


class AppointmentCreate(BaseModel):
    title: str
    scheduled_at: datetime
    notes: Optional[str] = None
    remind_before_minutes: int = 60
    family_member_id: Optional[int] = None

    @field_validator("title")
    @classmethod
    def _title_nonempty(cls, v: str) -> str:
        cleaned = (v or "").strip()
        if not cleaned:
            raise ValueError("Title is required")
        if len(cleaned) > 300:
            raise ValueError("Title must be at most 300 characters")
        return cleaned

    @field_validator("remind_before_minutes")
    @classmethod
    def _remind(cls, v: int) -> int:
        return normalize_remind_before_minutes(v)

    @field_validator("notes")
    @classmethod
    def _notes(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        cleaned = v.strip()
        return cleaned or None


class AppointmentUpdate(BaseModel):
    title: Optional[str] = None
    scheduled_at: Optional[datetime] = None
    notes: Optional[str] = None
    remind_before_minutes: Optional[int] = None
    # Omit = unchanged; null = clear to personal; int = reassign (owner-validated)
    family_member_id: Optional[int] = None
    is_active: Optional[bool] = None

    @field_validator("title")
    @classmethod
    def _title(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        cleaned = v.strip()
        if not cleaned:
            raise ValueError("Title is required")
        if len(cleaned) > 300:
            raise ValueError("Title must be at most 300 characters")
        return cleaned

    @field_validator("remind_before_minutes")
    @classmethod
    def _remind(cls, v: Optional[int]) -> Optional[int]:
        if v is None:
            return v
        return normalize_remind_before_minutes(v)


class AppointmentResponse(BaseModel):
    id: int
    user_id: int
    family_member_id: Optional[int] = None
    family_member_name: Optional[str] = None
    title: str
    scheduled_at: datetime
    notes: Optional[str] = None
    remind_before_minutes: int
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True
