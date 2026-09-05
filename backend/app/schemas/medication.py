from pydantic import BaseModel, field_validator
from typing import Optional, List
from datetime import datetime, date

# DB CHECK (medication_schedules_frequency_check) + Flutter Title Case labels
_FREQUENCY_ALIASES = {
    "daily": "daily",
    "twice daily": "twice_daily",
    "twice_daily": "twice_daily",
    "three times daily": "three_times_daily",
    "three_times_daily": "three_times_daily",
    "four times daily": "four_times_daily",
    "four_times_daily": "four_times_daily",
    "weekly": "weekly",
    "fortnightly": "fortnightly",
    "monthly": "monthly",
    "as needed": "as_needed",
    "as_needed": "as_needed",
}
_ALLOWED_FREQUENCIES = set(_FREQUENCY_ALIASES.values())


def normalize_medication_frequency(value: str) -> str:
    key = (value or "").strip().lower().replace("-", " ")
    key = " ".join(key.split())
    # also accept already-normalized snake_case after lower
    snake = key.replace(" ", "_")
    if snake in _ALLOWED_FREQUENCIES:
        return snake
    if key in _FREQUENCY_ALIASES:
        return _FREQUENCY_ALIASES[key]
    raise ValueError(
        f"Invalid frequency '{value}'. Allowed: {sorted(_ALLOWED_FREQUENCIES)}"
    )


class MedicationScheduleCreate(BaseModel):
    medicine_name: str
    dosage: Optional[str] = None
    frequency: str  # daily, twice_daily, three_times_daily, weekly, monthly, as_needed
    times: Optional[List[str]] = None  # ["08:00", "20:00"]
    instructions: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    refill_date: Optional[date] = None
    total_quantity: Optional[int] = None
    remaining_quantity: Optional[int] = None
    family_member_id: Optional[int] = None
    prescription_id: Optional[int] = None

    @field_validator("frequency")
    @classmethod
    def _normalize_frequency(cls, v: str) -> str:
        return normalize_medication_frequency(v)


class MedicationScheduleUpdate(BaseModel):
    medicine_name: Optional[str] = None
    dosage: Optional[str] = None
    frequency: Optional[str] = None
    times: Optional[List[str]] = None
    instructions: Optional[str] = None
    end_date: Optional[date] = None
    # Omit = unchanged; null = clear refill_date (HN-REM-009)
    refill_date: Optional[date] = None
    total_quantity: Optional[int] = None
    remaining_quantity: Optional[int] = None
    is_active: Optional[bool] = None
    # Omit field = unchanged; null = clear to personal; int = reassign (owner-validated)
    family_member_id: Optional[int] = None

    @field_validator("frequency")
    @classmethod
    def _normalize_frequency(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        return normalize_medication_frequency(v)


class MedicationScheduleResponse(BaseModel):
    id: int
    user_id: int
    family_member_id: Optional[int] = None
    family_member_name: Optional[str] = None
    medicine_name: str
    dosage: Optional[str] = None
    frequency: str
    times: Optional[List[str]] = None
    instructions: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    refill_date: Optional[date] = None
    total_quantity: Optional[int] = None
    remaining_quantity: Optional[int] = None
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True
