from pydantic import BaseModel
from typing import Optional, List, Any
from datetime import datetime, date


class ExtractedMedicine(BaseModel):
    name: str
    dosage: Optional[str] = None
    frequency: Optional[str] = None
    duration: Optional[str] = None
    instructions: Optional[str] = None


class PrescriptionScanResponse(BaseModel):
    id: int
    raw_text: Optional[str] = None
    medicines: List[ExtractedMedicine] = []
    doctor_name: Optional[str] = None
    hospital: Optional[str] = None
    summary: Optional[str] = None
    medical_record_id: Optional[int] = None


class PrescriptionResponse(BaseModel):
    id: int
    user_id: int
    family_member_id: Optional[int] = None
    medical_record_id: Optional[int] = None
    doctor_name: Optional[str] = None
    hospital: Optional[str] = None
    prescription_date: Optional[date] = None
    medicines: List[Any] = []   # list of ExtractedMedicine dicts
    ai_summary: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True
