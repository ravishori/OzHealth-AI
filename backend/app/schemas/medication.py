from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, date


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


class MedicationScheduleUpdate(BaseModel):
    medicine_name: Optional[str] = None
    dosage: Optional[str] = None
    frequency: Optional[str] = None
    times: Optional[List[str]] = None
    instructions: Optional[str] = None
    end_date: Optional[date] = None
    refill_date: Optional[date] = None
    remaining_quantity: Optional[int] = None
    is_active: Optional[bool] = None


class MedicationScheduleResponse(BaseModel):
    id: int
    user_id: int
    family_member_id: Optional[int] = None
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
