from pydantic import BaseModel, field_validator, model_validator
from typing import Optional, List
from datetime import datetime, timedelta, timezone
import math


# Canonical types already used by the API, Flutter log form, and METRIC_UNITS.
ALLOWED_METRIC_TYPES = frozenset(
    {
        "blood_pressure",
        "blood_pressure_systolic",
        "blood_pressure_diastolic",
        "blood_sugar",
        "heart_rate",
        "oxygen_saturation",
        "oxygen_level",
        "weight",
        "height",
        "bmi",
        "temperature",
    }
)


class HealthMetricCreate(BaseModel):
    metric_type: str
    value: float
    value2: Optional[float] = None
    unit: Optional[str] = None
    notes: Optional[str] = None
    family_member_id: Optional[int] = None
    recorded_at: Optional[datetime] = None

    @field_validator("metric_type")
    @classmethod
    def _metric_type_required_and_known(cls, v: str) -> str:
        key = (v or "").strip()
        if not key:
            raise ValueError("metric_type is required")
        if key not in ALLOWED_METRIC_TYPES:
            raise ValueError("unsupported metric_type")
        return key

    @field_validator("value")
    @classmethod
    def _value_finite(cls, v: float) -> float:
        if v is None or not math.isfinite(v):
            raise ValueError("value must be a finite number")
        return v

    @field_validator("value2")
    @classmethod
    def _value2_finite(cls, v: Optional[float]) -> Optional[float]:
        if v is None:
            return v
        if not math.isfinite(v):
            raise ValueError("value2 must be a finite number")
        return v

    @field_validator("notes")
    @classmethod
    def _notes_trim(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        text = v.strip()
        if len(text) > 2000:
            raise ValueError("notes too long")
        return text or None

    @field_validator("family_member_id")
    @classmethod
    def _family_id(cls, v: Optional[int]) -> Optional[int]:
        if v is None:
            return v
        if v < 1:
            raise ValueError("family_member_id must be a positive integer")
        return v

    @field_validator("recorded_at")
    @classmethod
    def _recorded_at_tz(cls, v: Optional[datetime]) -> Optional[datetime]:
        if v is None:
            return v
        if v.tzinfo is None:
            v = v.replace(tzinfo=timezone.utc)
        return v

    @model_validator(mode="after")
    def _clinical_payload(self) -> "HealthMetricCreate":
        if self.metric_type == "blood_pressure" and self.value2 is None:
            raise ValueError("blood pressure requires systolic (value) and diastolic (value2)")
        if self.recorded_at is not None:
            now = datetime.now(timezone.utc)
            if self.recorded_at > now + timedelta(minutes=5):
                raise ValueError("recorded_at cannot be in the future")
        return self


class HealthMetricUpdate(BaseModel):
    """Editable fields for an existing reading. Type and family subject are frozen."""

    value: float
    value2: Optional[float] = None
    unit: Optional[str] = None
    notes: Optional[str] = None
    recorded_at: Optional[datetime] = None

    @field_validator("value")
    @classmethod
    def _value_finite(cls, v: float) -> float:
        if v is None or not math.isfinite(v):
            raise ValueError("value must be a finite number")
        return v

    @field_validator("value2")
    @classmethod
    def _value2_finite(cls, v: Optional[float]) -> Optional[float]:
        if v is None:
            return v
        if not math.isfinite(v):
            raise ValueError("value2 must be a finite number")
        return v

    @field_validator("notes")
    @classmethod
    def _notes_trim(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        text = v.strip()
        if len(text) > 2000:
            raise ValueError("notes too long")
        return text or None

    @field_validator("recorded_at")
    @classmethod
    def _recorded_at_tz(cls, v: Optional[datetime]) -> Optional[datetime]:
        if v is None:
            return v
        if v.tzinfo is None:
            v = v.replace(tzinfo=timezone.utc)
        now = datetime.now(timezone.utc)
        if v > now + timedelta(minutes=5):
            raise ValueError("recorded_at cannot be in the future")
        return v


class HealthMetricResponse(BaseModel):
    id: int
    user_id: int
    family_member_id: Optional[int] = None
    metric_type: str
    value: float
    value2: Optional[float] = None
    unit: Optional[str] = None
    notes: Optional[str] = None
    recorded_at: datetime

    class Config:
        from_attributes = True


class HealthMetricSummary(BaseModel):
    metric_type: str
    latest_value: float
    latest_value2: Optional[float] = None
    unit: Optional[str] = None
    recorded_at: datetime
    trend: str  # up, down, stable — direction of recorded values only
    history: List[HealthMetricResponse]
