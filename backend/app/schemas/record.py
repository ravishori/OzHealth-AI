from pydantic import BaseModel
from typing import Optional
from datetime import datetime, date


class MedicalRecordResponse(BaseModel):
    id: int
    user_id: int
    family_member_id: Optional[int] = None
    record_type: str   # prescription, lab_report, radiology, discharge_summary, other
    title: Optional[str] = None
    file_url: Optional[str] = None
    file_name: Optional[str] = None
    file_size: Optional[int] = None
    file_type: Optional[str] = None
    notes: Optional[str] = None
    record_date: Optional[date] = None
    is_active: bool = True
    created_at: datetime

    class Config:
        from_attributes = True


class MedicalRecordUploadResponse(BaseModel):
    id: int
    title: Optional[str] = None
    file_url: str
    file_type: str
    record_type: str
    created_at: datetime

    class Config:
        from_attributes = True
