"""
Pydantic schemas for the ePrescription feature.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, List, Optional

from pydantic import BaseModel, field_validator


# ─── Validate request ─────────────────────────────────────────────────────────

class EPrescriptionValidateRequest(BaseModel):
    """POST /eprescriptions/validate — body sent by the Flutter app."""
    token: str                  # raw QR value / manual entry (never stored)
    provider: str = "erx"       # only eRx Script Exchange (NPDS) is supported

    @field_validator("provider")
    @classmethod
    def _check_provider(cls, v: str) -> str:
        if v != "erx":
            raise ValueError("Only 'erx' is supported. MediSecure is discontinued.")
        return v

    @field_validator("token")
    @classmethod
    def _check_token(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 4:
            raise ValueError("Token is too short")
        if len(v) > 1000:
            raise ValueError("Token is too long")
        return v


# ─── Medicine sub-schema ──────────────────────────────────────────────────────

class EPrescriptionMedicine(BaseModel):
    name:          str
    generic_name:  Optional[str] = None
    dosage:        Optional[str] = None
    frequency:     Optional[str] = None
    quantity:      Optional[str] = None
    repeats:       Optional[int] = None
    instructions:  Optional[str] = None
    # TGA enrichment fields (populated when a TGA match is found)
    drug_class:    Optional[str] = None
    side_effects:  Optional[str] = None
    warnings:      Optional[str] = None
    schedule:      Optional[str] = None        # S4 / S8 / OTC etc.
    tga_registered: Optional[bool] = None


# ─── Responses ────────────────────────────────────────────────────────────────

class EPrescriptionResponse(BaseModel):
    """Full detail response — returned after validate and on GET /{id}."""
    id:                         int
    provider:                   str
    status:                     str
    token_last4:                Optional[str]
    patient_name:               Optional[str]
    prescriber_name:            Optional[str]
    prescriber_provider_number: Optional[str]
    prescriber_practice:        Optional[str]
    medicines:                  List[EPrescriptionMedicine] = []
    prescription_date:          Optional[datetime]
    expiry_date:                Optional[datetime]
    tga_enriched:               bool
    saved_to_records:           bool = False
    created_at:                 datetime

    class Config:
        from_attributes = True


class EPrescriptionListItem(BaseModel):
    """Lightweight item used in GET /eprescriptions/ list."""
    id:                int
    provider:          str
    status:            str
    token_last4:       Optional[str]
    patient_name:      Optional[str]
    prescriber_name:   Optional[str]
    medicine_count:    int = 0
    prescription_date: Optional[datetime]
    saved_to_records:  bool = False
    created_at:        datetime

    class Config:
        from_attributes = True


# ─── Refill Reminder schemas ──────────────────────────────────────────────────

class RefillReminderCreate(BaseModel):
    medicine_name: str
    refill_date:   datetime
    note:          Optional[str] = None

    @field_validator("medicine_name")
    @classmethod
    def _check_name(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("medicine_name is required")
        return v


class RefillReminderResponse(BaseModel):
    id:            int
    ep_id:         int
    medicine_name: str
    refill_date:   datetime
    note:          Optional[str]
    is_notified:   bool
    created_at:    datetime

    class Config:
        from_attributes = True


# ─── Share schemas ────────────────────────────────────────────────────────────

class ShareCreate(BaseModel):
    family_member_id: int


class ShareResponse(BaseModel):
    id:                 int
    ep_id:              int
    family_member_id:   int
    family_member_name: Optional[str]
    shared_at:          datetime

    class Config:
        from_attributes = True


# ─── Drug Interaction schemas ─────────────────────────────────────────────────

class InteractionCheckResponse(BaseModel):
    ep_id:               int
    medicines_checked:   List[str]
    interaction_analysis: Any
    duplicate_check:     Any = None
