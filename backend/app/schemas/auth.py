from pydantic import BaseModel, EmailStr
from typing import Optional


class SendOTPRequest(BaseModel):
    identifier: str  # email or phone
    purpose: str = "auth"  # auth, register


class VerifyOTPRequest(BaseModel):
    identifier: str
    otp_code: str
    purpose: str = "auth"


class RegisterRequest(BaseModel):
    name: str
    identifier: str  # email or phone
    otp_code: str
    age: Optional[int] = None
    gender: Optional[str] = None
    blood_group: Optional[str] = None


class LoginRequest(BaseModel):
    identifier: str
    otp_code: str


class RefreshTokenRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user_id: int
    name: str
    is_new_user: bool = False
