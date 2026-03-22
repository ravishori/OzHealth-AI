from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class UserUpdate(BaseModel):
    name: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    blood_group: Optional[str] = None
    health_conditions: Optional[List[str]] = None
    allergies: Optional[List[str]] = None
    lifestyle_preferences: Optional[dict] = None
    fcm_token: Optional[str] = None


class UserResponse(BaseModel):
    id: int
    name: str
    email: Optional[str] = None
    phone: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    blood_group: Optional[str] = None
    health_conditions: Optional[List[str]] = None
    allergies: Optional[List[str]] = None
    profile_image_url: Optional[str] = None
    is_verified: bool
    created_at: datetime

    class Config:
        from_attributes = True
