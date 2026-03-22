from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class HealthMetricCreate(BaseModel):
    metric_type: str
    value: float
    value2: Optional[float] = None
    unit: Optional[str] = None
    notes: Optional[str] = None
    family_member_id: Optional[int] = None
    recorded_at: Optional[datetime] = None


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
