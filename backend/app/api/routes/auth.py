from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime, timedelta, timezone
import logging
import re
import smtplib
from email.mime.text import MIMEText
from twilio.rest import Client

from app.core.database import get_db
from app.core.security import generate_otp, create_access_token, create_refresh_token, decode_token
from app.core.config import settings
from app.models.user import User
from app.models.otp import OTP
from app.schemas.auth import (
    SendOTPRequest, VerifyOTPRequest, RegisterRequest,
    LoginRequest, RefreshTokenRequest, TokenResponse
)

router = APIRouter()
logger = logging.getLogger(__name__)

# =========================
# Twilio Setup
# =========================

twilio_client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)

# =========================
# Utility Functions
# =========================

def is_email(identifier: str):
    return "@" in identifier


def is_phone(identifier: str):
    return re.match(r"^\+?[1-9]\d{7,14}$", identifier)


# =========================
# Send Email OTP
# =========================

def send_email_otp(email: str, otp: str):

    subject = "Your Verification OTP"
    body = f"""
Hello,

Your verification OTP is: {otp}

This OTP will expire in {settings.OTP_EXPIRY_MINUTES} minutes.

Do not share this OTP with anyone.

Regards
Health AI Team
"""

    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = settings.SMTP_EMAIL
    msg["To"] = email

    try:
        with smtplib.SMTP(settings.SMTP_SERVER, settings.SMTP_PORT) as server:
            server.starttls()
            server.login(settings.SMTP_EMAIL, settings.SMTP_PASSWORD)
            server.sendmail(settings.SMTP_EMAIL, email, msg.as_string())

    except Exception as e:
        logger.error(f"Email sending failed: {e}")


# =========================
# Send SMS OTP
# =========================

def send_sms_otp(phone: str, otp: str):

    try:

        message = twilio_client.messages.create(
            body=f"Your verification OTP is {otp}. It expires in {settings.OTP_EXPIRY_MINUTES} minutes.",
            from_=settings.TWILIO_PHONE_NUMBER,
            to=phone
        )

        logger.info(f"SMS sent SID: {message.sid}")

    except Exception as e:
        logger.error(f"SMS sending failed: {e}")


# =========================
# SEND OTP
# =========================

@router.post("/send-otp")
async def send_otp(req: SendOTPRequest, db: AsyncSession = Depends(get_db)):

    otp_code = generate_otp()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=settings.OTP_EXPIRY_MINUTES)

    otp = OTP(
        identifier=req.identifier,
        otp_code=otp_code,
        purpose=req.purpose,
        expires_at=expires_at,
    )

    db.add(otp)
    await db.commit()

    # Send OTP

    if is_email(req.identifier):
        send_email_otp(req.identifier, otp_code)

    elif is_phone(req.identifier):
        send_sms_otp(req.identifier, otp_code)

    else:
        raise HTTPException(status_code=400, detail="Invalid email or phone number")

    logger.info(f"[OTP] {req.identifier} → {otp_code}")

    return {
        "message": "OTP sent successfully",
        "expires_in_minutes": settings.OTP_EXPIRY_MINUTES
    }


# =========================
# REGISTER
# =========================

@router.post("/register", response_model=TokenResponse)
async def register(req: RegisterRequest, db: AsyncSession = Depends(get_db)):

    result = await db.execute(
        select(OTP).where(
            OTP.identifier == req.identifier,
            OTP.otp_code == req.otp_code,
            OTP.purpose == "register",
            OTP.is_used == False,
            OTP.expires_at > datetime.now(timezone.utc),
        ).order_by(OTP.created_at.desc())
    )

    otp = result.scalar_one_or_none()

    if not otp:
        raise HTTPException(status_code=400, detail="Invalid or expired OTP")

    if is_email(req.identifier):
        existing = await db.execute(select(User).where(User.email == req.identifier))
    else:
        existing = await db.execute(select(User).where(User.phone == req.identifier))

    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="User already registered")

    user = User(
        name=req.name,
        email=req.identifier if is_email(req.identifier) else None,
        phone=req.identifier if not is_email(req.identifier) else None,
        age=req.age,
        gender=req.gender,
        blood_group=req.blood_group,
        is_verified=True,
    )

    db.add(user)
    otp.is_used = True

    await db.commit()
    await db.refresh(user)

    access_token = create_access_token({"sub": str(user.id)})
    refresh_token = create_refresh_token({"sub": str(user.id)})

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user.id,
        name=user.name,
        is_new_user=True,
    )


# =========================
# LOGIN
# =========================

@router.post("/login", response_model=TokenResponse)
async def login(req: LoginRequest, db: AsyncSession = Depends(get_db)):

    result = await db.execute(
        select(OTP).where(
            OTP.identifier == req.identifier,
            OTP.otp_code == req.otp_code,
            OTP.purpose == "auth",
            OTP.is_used == False,
            OTP.expires_at > datetime.now(timezone.utc),
        ).order_by(OTP.created_at.desc())
    )

    otp = result.scalar_one_or_none()

    if not otp:
        raise HTTPException(status_code=400, detail="Invalid or expired OTP")

    if is_email(req.identifier):
        user_result = await db.execute(select(User).where(User.email == req.identifier))
    else:
        user_result = await db.execute(select(User).where(User.phone == req.identifier))

    user = user_result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    otp.is_used = True
    await db.commit()

    access_token = create_access_token({"sub": str(user.id)})
    refresh_token = create_refresh_token({"sub": str(user.id)})

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user.id,
        name=user.name,
    )


# =========================
# REFRESH TOKEN
# =========================

@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(req: RefreshTokenRequest, db: AsyncSession = Depends(get_db)):

    payload = decode_token(req.refresh_token)

    user_id = payload.get("sub")
    token_type = payload.get("type")

    if not user_id or token_type != "refresh":
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    result = await db.execute(select(User).where(User.id == int(user_id)))
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    access_token = create_access_token({"sub": str(user.id)})
    new_refresh_token = create_refresh_token({"sub": str(user.id)})

    return TokenResponse(
        access_token=access_token,
        refresh_token=new_refresh_token,
        user_id=user.id,
        name=user.name,
    )