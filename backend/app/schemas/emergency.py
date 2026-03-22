from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class EmergencyContactCreate(BaseModel):
    name: str
    phone: str
    relationship: Optional[str] = None
    is_primary: bool = False


class EmergencyContactResponse(BaseModel):
    id: int
    user_id: int
    name: str
    phone: str
    relationship: Optional[str] = None
    is_primary: bool
    created_at: datetime

    class Config:
        from_attributes = True


class SOSRequest(BaseModel):
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    message: Optional[str] = None


class SOSResponse(BaseModel):
    success: bool
    contacts_notified: int
    message: str
    location_url: Optional[str] = None
