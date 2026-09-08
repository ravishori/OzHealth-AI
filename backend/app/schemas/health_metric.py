from pydantic import BaseModel, Field, field_validator
from typing import Optional, List
from datetime import datetime
import math


class HealthMetricCreate(BaseModel):
    metric_type: str
    value: float
    value2: Optional[float] = None
    unit: Optional[str] = None
    notes: Optional[str] = None
    family_member_id: Optional[int] = None
    recorded_at: Optional[datetime] = None


class HealthMetricUpdate(BaseModel):
    """HN-HEALTH-005 — editable fields only.

    Server-owned / identity fields (id, user_id, created_at, metric_type,
    family_member_id) are not part of this schema and are ignored if supplied.
    Ordinary corrections preserve family ownership.
    """

    value: Optional[float] = None
    value2: Optional[float] = None
    unit: Optional[str] = Field(None, max_length=50)
    notes: Optional[str] = Field(None, max_length=2000)
    recorded_at: Optional[datetime] = None

    @field_validator("value", "value2", mode="before")
    @classmethod
    def _finite_number(cls, v):
        if v is None:
            return v
        try:
            n = float(v)
        except (TypeError, ValueError) as exc:
            raise ValueError("must be a number") from exc
        if not math.isfinite(n):
            raise ValueError("must be a finite number")
        return n

    @field_validator("unit", "notes", mode="before")
    @classmethod
    def _empty_str_to_none(cls, v):
        if isinstance(v, str) and not v.strip():
            return None
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
    trend: str  # up, down, stable
    history: List[HealthMetricResponse]
