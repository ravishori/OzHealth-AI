from pydantic import BaseModel, Field, field_validator
from typing import Optional, List, Any
from datetime import datetime, date


class ExtractedMedicine(BaseModel):
    name: str
    dosage: Optional[str] = None
    frequency: Optional[str] = None
    duration: Optional[str] = None
    instructions: Optional[str] = None


class ManualMedicineEntry(BaseModel):
    """User-supplied medicine row for HN-RX-003 manual prescription entry."""

    name: str = Field(..., min_length=1, max_length=500)
    dosage: Optional[str] = Field(None, max_length=200)
    frequency: Optional[str] = Field(None, max_length=200)
    duration: Optional[str] = Field(None, max_length=200)
    instructions: Optional[str] = Field(None, max_length=1000)
    quantity: Optional[str] = Field(None, max_length=100)
    catalog_medicine_id: Optional[int] = Field(None, ge=1)
    medicine_id: Optional[int] = Field(None, ge=1)
    artg_number: Optional[str] = Field(None, max_length=64)
    match_status: Optional[str] = Field(None, max_length=32)

    @field_validator("name")
    @classmethod
    def _name_non_blank(cls, v: str) -> str:
        cleaned = (v or "").strip()
        if not cleaned:
            raise ValueError("Medicine name is required")
        return cleaned


class ManualPrescriptionCreate(BaseModel):
    """POST /prescriptions/manual request body — no OCR file, no LLM."""

    medicines: List[ManualMedicineEntry] = Field(..., min_length=1)
    doctor_name: Optional[str] = Field(None, max_length=255)
    hospital: Optional[str] = Field(None, max_length=500)
    family_member_id: Optional[int] = Field(None, ge=1)

    @field_validator("doctor_name", "hospital", mode="before")
    @classmethod
    def _blank_to_none(cls, v):
        if v is None:
            return None
        if isinstance(v, str):
            s = v.strip()
            return s or None
        return v


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
    entry_mode: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True
