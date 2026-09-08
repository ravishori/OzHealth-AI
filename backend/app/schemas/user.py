from pydantic import BaseModel, Field, field_validator
from typing import Optional, List, Any
from datetime import datetime
import json


_LIFESTYLE_MAX_KEYS = 20
_LIFESTYLE_MAX_KEY_LEN = 64
_LIFESTYLE_MAX_VALUE_LEN = 200
_LIFESTYLE_MAX_JSON_BYTES = 4000


class UserUpdate(BaseModel):
    name: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    blood_group: Optional[str] = None
    health_conditions: Optional[List[str]] = None
    allergies: Optional[List[str]] = None
    # HN-PROF-006 — encrypted JSON object of string preference fields.
    lifestyle_preferences: Optional[dict] = None
    fcm_token: Optional[str] = None
    suburb: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    postcode: Optional[str] = None
    phone2: Optional[str] = None

    @field_validator("lifestyle_preferences", mode="before")
    @classmethod
    def _lifestyle_object(cls, v: Any):
        if v is None:
            return None
        if not isinstance(v, dict):
            raise ValueError("lifestyle_preferences must be an object")
        if len(v) > _LIFESTYLE_MAX_KEYS:
            raise ValueError("lifestyle_preferences has too many keys")
        cleaned: dict[str, str] = {}
        for key, raw in v.items():
            if not isinstance(key, str) or not key.strip():
                raise ValueError("lifestyle_preferences keys must be non-empty strings")
            key = key.strip()
            if len(key) > _LIFESTYLE_MAX_KEY_LEN:
                raise ValueError("lifestyle_preferences key too long")
            if raw is None:
                continue
            if not isinstance(raw, str):
                raise ValueError("lifestyle_preferences values must be strings")
            val = raw.strip()
            if not val:
                continue
            if len(val) > _LIFESTYLE_MAX_VALUE_LEN:
                raise ValueError("lifestyle_preferences value too long")
            cleaned[key] = val
        encoded = json.dumps(cleaned, ensure_ascii=False)
        if len(encoded.encode("utf-8")) > _LIFESTYLE_MAX_JSON_BYTES:
            raise ValueError("lifestyle_preferences payload too large")
        return cleaned


class UserResponse(BaseModel):
    id: int
    name: str
    email: Optional[str] = None
    phone: Optional[str] = None
    phone2: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    blood_group: Optional[str] = None
    health_conditions: Optional[List[str]] = None
    allergies: Optional[List[str]] = None
    # HN-PROF-006 — decrypted lifestyle preference object for the owner.
    lifestyle_preferences: Optional[dict] = None
    profile_image_url: Optional[str] = None
    suburb: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    postcode: Optional[str] = None
    is_verified: bool
    created_at: datetime

    class Config:
        from_attributes = True


class RequestContactChangeRequest(BaseModel):
    contact_type: str          # "email" or "phone"
    new_value: str             # new email address or phone number


class ConfirmContactChangeRequest(BaseModel):
    contact_type: str          # "email" or "phone"
    new_value: str             # must match what was requested
    otp_code: str              # 6-digit OTP received on new_value
