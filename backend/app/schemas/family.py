from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class FamilyMemberCreate(BaseModel):
    name: str
    relationship: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    blood_group: Optional[str] = None
    medical_conditions: Optional[List[str]] = None
    allergies: Optional[List[str]] = None
    notes: Optional[str] = None


class FamilyMemberUpdate(BaseModel):
    name: Optional[str] = None
    relationship: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    blood_group: Optional[str] = None
    medical_conditions: Optional[List[str]] = None
    allergies: Optional[List[str]] = None
    notes: Optional[str] = None


class FamilyMemberResponse(BaseModel):
    id: int
    user_id: int
    name: str
    relationship: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    blood_group: Optional[str] = None
    medical_conditions: Optional[List[str]] = None
    allergies: Optional[List[str]] = None
    notes: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True
