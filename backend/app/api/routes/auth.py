from fastapi import APIRouter, Depends, HTTPException
from app.core.log_decorator import LoggedAPIRoute, log_fn
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text
from datetime import datetime, timedelta, timezone
import logging
import re
import asyncio

from app.core.database import get_db
from app.core.security import (
    generate_otp, hash_otp, verify_otp,
    create_access_token, create_refresh_token, decode_token,
)
from app.core.config import settings
from app.core.exceptions import RateLimitError, ValidationError as AppValidationError
from app.core.logging_config import audit_log
from app.models.user import User
from app.models.otp import OTP
from app.schemas.auth import (
    SendOTPRequest, VerifyOTPRequest, RegisterRequest,
    LoginRequest, RefreshTokenRequest, TokenResponse
)
from app.services.cache_service import CacheService

# ---------------------------------------------------------------------------
# Stored-procedure call helpers
# ---------------------------------------------------------------------------

@log_fn
async def _sp_insert_otp(
    db: AsyncSession,
    identifier: str,
    otp_code: str,
    otp_hash: str,
    purpose: str,
    expires_at: datetime,
) -> None:
    """Insert an OTP record via sp_insert_otp stored procedure."""
    await db.execute(
        text("SELECT * FROM sp_insert_otp(:identifier, :otp_code, :otp_hash, :purpose, :expires_at)"),
        {
            "identifier": identifier,
            "otp_code":   otp_code,
            "otp_hash":   otp_hash,
            "purpose":    purpose,
            "expires_at": expires_at,
        },
    )


@log_fn
async def _fn_get_valid_otps(db: AsyncSession, identifier: str, purpose: str):
    """Return rows from fn_get_valid_otps — each row has id, otp_code, otp_hash, created_at."""
    result = await db.execute(
        text("SELECT * FROM fn_get_valid_otps(:identifier, :purpose)"),
        {"identifier": identifier, "purpose": purpose},
    )
    return result.fetchall()


@log_fn
async def _sp_mark_otp_used(db: AsyncSession, otp_id: int) -> None:
    """Mark a single OTP as used via sp_mark_otp_used stored procedure."""
    await db.execute(
        text("SELECT sp_mark_otp_used(:otp_id)"),
        {"otp_id": otp_id},
    )


@log_fn
async def _sp_insert_user(
    db: AsyncSession,
    name: str,
    email: str | None,
    phone: str | None,
    age: int | None,
    gender: str | None,
    blood_group: str | None,
):
    """Insert a user via sp_insert_user and return the first result row (id, created_at)."""
    result = await db.execute(
        text(
            "SELECT * FROM sp_insert_user("
            ":name, :email, :phone, :age, :gender, :blood_group"
            ")"
        ),
        {
            "name":        name,
            "email":       email,
            "phone":       phone,
            "age":         age,
            "gender":      gender,
            "blood_group": blood_group,
        },
    )
    return result.fetchone()


@log_fn
async def _fn_get_user_by_identifier(db: AsyncSession, identifier: str):
    """Look up an active user by email or phone via fn_get_user_by_identifier."""
    result = await db.execute(
        text("SELECT * FROM fn_get_user_by_identifier(:identifier)"),
        {"identifier": identifier},
    )
    return result.fetchone()

router = APIRouter(route_class=LoggedAPIRoute)
logger = logging.getLogger(__name__)

# =========================
# Utility Functions
# =========================

def is_email(identifier: str) -> bool:
    return "@" in identifier and "." in identifier.split("@")[-1]


def is_phone(identifier: str) -> bool:
    return bool(re.match(r"^\+?[1-9]\d{7,14}$", identifier))


def _mask(identifier: str) -> str:
    """Mask email/phone for safe logging."""
    return identifier[:4] + "***" if len(identifier) > 4 else "****"


# =========================
# Rate limiting helpers
# =========================

async def _check_otp_send_rate(identifier: str):
    """Raise RateLimitError if OTP send limit exceeded."""
    key = f"otp_rate:send:{identifier}"
    count = await CacheService.increment_counter(key, ttl=settings.OTP_SEND_WINDOW)
    if count > settings.OTP_SEND_LIMIT:
        retry_after = await CacheService.get_ttl(key)
        raise RateLimitError(
            f"Too many OTP requests. Try again in {retry_after} seconds.",
            retry_after=retry_after,
        )


async def _check_otp_verify_rate(identifier: str):
    """Raise RateLimitError if OTP verification attempt limit exceeded."""
    key = f"otp_rate:verify:{identifier}"
    count = await CacheService.increment_counter(key, ttl=settings.OTP_VERIFY_WINDOW)
    if count > settings.OTP_VERIFY_LIMIT:
        retry_after = await CacheService.get_ttl(key)
        raise RateLimitError(
            f"Too many failed attempts. Try again in {retry_after} seconds.",
            retry_after=retry_after,
        )


async def _clear_verify_rate(identifier: str):
    """Clear failed attempt counter on successful verification."""
    await CacheService.delete(f"otp_rate:verify:{identifier}")


# =========================
# Send Email OTP (with retry)
# =========================

def _send_email_otp(email: str, otp: str) -> bool:
    """
    Send OTP via SMTP.  Runs in a thread pool (called via asyncio.to_thread)
    so it never blocks the async event loop.

    Retry policy: 2 attempts, 5 s socket timeout, 1 s gap between attempts.
    Total worst-case: 5 + 1 + 5 = 11 s — well under Dio's receiveTimeout.
    """
    import smtplib
    import time
    from email.mime.multipart import MIMEMultipart
    from email.mime.text import MIMEText as MIMETextPart

    if not settings.SMTP_EMAIL or not settings.SMTP_PASSWORD:
        logger.warning("SMTP credentials not configured — email OTP not sent")
        return False

    subject = f"Your {settings.APP_NAME} Verification Code"

    html_body = f"""
<!DOCTYPE html>
<html>
<body style="font-family: Arial, sans-serif; background:#f4f4f4; margin:0; padding:20px;">
  <div style="max-width:480px; margin:0 auto; background:#fff; border-radius:8px; overflow:hidden;">
    <div style="background:#00897B; padding:24px; text-align:center;">
      <h1 style="color:#fff; margin:0; font-size:22px;">{settings.APP_NAME}</h1>
      <p style="color:#e0f2f1; margin:4px 0 0;">Your Health Companion</p>
    </div>
    <div style="padding:32px 24px;">
      <h2 style="color:#333; margin:0 0 8px;">Verification Code</h2>
      <p style="color:#666; margin:0 0 24px;">
        Use the code below to verify your identity. It expires in
        <strong>{settings.OTP_EXPIRY_MINUTES} minutes</strong>.
      </p>
      <div style="background:#e8f5e9; border-radius:8px; padding:20px; text-align:center; margin-bottom:24px;">
        <span style="font-size:36px; font-weight:bold; letter-spacing:8px; color:#00897B;">
          {otp}
        </span>
      </div>
      <p style="color:#999; font-size:12px; margin:0;">
        Never share this code. {settings.APP_NAME} will never ask for your OTP.
      </p>
    </div>
  </div>
</body>
</html>"""

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = settings.SMTP_EMAIL
    msg["To"] = email
    msg.attach(MIMETextPart(
        f"Your {settings.APP_NAME} OTP: {otp}\nExpires in {settings.OTP_EXPIRY_MINUTES} minutes.",
        "plain",
    ))
    msg.attach(MIMETextPart(html_body, "html"))

    # 2 attempts, 5 s timeout each → worst case 5 + 1 + 5 = 11 s (in a thread)
    for attempt in range(1, 3):
        try:
            with smtplib.SMTP(settings.SMTP_SERVER, settings.SMTP_PORT, timeout=5) as server:
                server.ehlo()
                server.starttls()
                server.login(settings.SMTP_EMAIL, settings.SMTP_PASSWORD)
                server.sendmail(settings.SMTP_EMAIL, email, msg.as_string())
            logger.info("OTP email sent to %s on attempt %d", _mask(email), attempt)
            return True
        except Exception as exc:
            logger.warning("Email attempt %d/2 failed for %s: %s", attempt, _mask(email), exc)
            if attempt < 2:
                time.sleep(1)

    logger.error("All email send attempts failed for %s", _mask(email))
    return False


# =========================
# Send SMS OTP (lazy Twilio)
# =========================

def _send_sms_otp(phone: str, otp: str) -> bool:
    """Send OTP via Twilio SMS. Returns True on success."""
    if not settings.TWILIO_ACCOUNT_SID or not settings.TWILIO_AUTH_TOKEN:
        logger.warning("Twilio credentials not configured — SMS OTP not sent")
        return False

    try:
        from twilio.rest import Client
        client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
        message = client.messages.create(
            body=(
                f"Your {settings.APP_NAME} verification code is {otp}. "
                f"Expires in {settings.OTP_EXPIRY_MINUTES} minutes. Do not share."
            ),
            from_=settings.TWILIO_PHONE_NUMBER,
            to=phone,
        )
        logger.info("SMS sent SID: %s to %s", message.sid, _mask(phone))
        return True
    except Exception as exc:
        logger.error("SMS send failed for %s: %s", _mask(phone), exc)
        return False


# =========================
# SEND OTP
# =========================

@router.post("/send-otp")
async def send_otp(req: SendOTPRequest, db: AsyncSession = Depends(get_db)):
    # Validate identifier format
    if not is_email(req.identifier) and not is_phone(req.identifier):
        raise HTTPException(status_code=400, detail="Invalid email or phone number format")

    # Rate limiting — max N sends per identifier per window
    await _check_otp_send_rate(req.identifier)

    otp_code = generate_otp()
    otp_hash = hash_otp(otp_code)  # HMAC-SHA256 hex digest — never stored plaintext alone
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=settings.OTP_EXPIRY_MINUTES)

    # Persist both plain OTP (for dev logging) and hash (for verification) via stored procedure
    await _sp_insert_otp(
        db,
        identifier=req.identifier,
        otp_code=otp_code,
        otp_hash=otp_hash,
        purpose=req.purpose,
        expires_at=expires_at,
    )
    await db.commit()

    # Send OTP in a thread-pool so the blocking smtplib / twilio calls
    # never freeze the async event loop (SMTP can take 10 s × 3 retries).
    sent = False
    if is_email(req.identifier):
        sent = await asyncio.to_thread(_send_email_otp, req.identifier, otp_code)
    else:
        sent = await asyncio.to_thread(_send_sms_otp, req.identifier, otp_code)

    # Dev fallback — log the FULL OTP so developers can test without email/SMS
    # This line must be removed (or disabled by setting DEBUG=false) before going to production
    if settings.DEBUG:
        logger.info(
            "[DEV OTP] identifier=%s  otp=%s  purpose=%s  expires=%s",
            _mask(req.identifier), otp_code, req.purpose, expires_at.strftime("%H:%M:%S UTC"),
        )

    if not sent and not settings.DEBUG:
        raise HTTPException(
            status_code=502,
            detail="Failed to send OTP. Please check your email/phone and try again.",
        )

    # Audit log — masked identifier, no OTP code
    audit_log.info(
        "otp_sent",
        extra={"identifier": _mask(req.identifier), "purpose": req.purpose},
    )

    return {
        "message": "OTP sent successfully" if sent else "OTP generated (dev mode — check server logs)",
        "expires_in_minutes": settings.OTP_EXPIRY_MINUTES,
    }


# =========================
# VERIFY OTP (standalone — does NOT consume the OTP)
# =========================

@router.post("/verify-otp")
async def verify_otp_check(req: VerifyOTPRequest, db: AsyncSession = Depends(get_db)):
    """
    Pre-validate an OTP without consuming it or creating a session.

    Use this before the final register/login step to give the user instant
    feedback that their code is correct, without committing any DB changes.
    The OTP remains valid and must be re-sent to /register or /login to
    actually authenticate.
    """
    # Apply the same rate limit as full verification
    await _check_otp_verify_rate(req.identifier)

    # Fetch valid (unexpired, unused) OTPs
    otp_rows = await _fn_get_valid_otps(db, req.identifier, req.purpose)

    # Constant-time comparison against stored hashes
    for row in otp_rows:
        if verify_otp(req.otp_code, row.otp_hash):
            # Clear failed-attempt counter on success
            await _clear_verify_rate(req.identifier)
            audit_log.info(
                "otp_pre_verified",
                extra={"identifier": _mask(req.identifier), "purpose": req.purpose},
            )
            return {"valid": True, "message": "OTP verified successfully"}

    raise HTTPException(status_code=400, detail="Invalid or expired OTP")


# =========================
# REGISTER
# =========================

@router.post("/register", response_model=TokenResponse)
async def register(req: RegisterRequest, db: AsyncSession = Depends(get_db)):
    # Rate limiting on verification attempts
    await _check_otp_verify_rate(req.identifier)

    # Fetch all valid (unexpired, unused) OTPs via stored function
    otp_rows = await _fn_get_valid_otps(db, req.identifier, "register")

    # Verify OTP against stored HMAC-SHA256 hashes (constant-time comparison)
    matched_otp = None
    for row in otp_rows:
        if verify_otp(req.otp_code, row.otp_hash):
            matched_otp = row
            break

    if not matched_otp:
        raise HTTPException(status_code=400, detail="Invalid or expired OTP")

    # Clear failed-attempt counter on success
    await _clear_verify_rate(req.identifier)

    # Create the user via stored procedure (raises 23505 on duplicate email/phone)
    try:
        user_row = await _sp_insert_user(
            db,
            name=req.name,
            email=req.identifier if is_email(req.identifier) else None,
            phone=req.identifier if not is_email(req.identifier) else None,
            age=req.age,
            gender=req.gender,
            blood_group=req.blood_group,
        )
    except Exception as exc:
        err_str = str(exc)
        if "23505" in err_str or "already exists" in err_str.lower():
            raise HTTPException(status_code=400, detail="User already registered")
        raise

    # Mark OTP as used via stored procedure
    await _sp_mark_otp_used(db, matched_otp.id)
    await db.commit()

    user_id = user_row.id
    user_name = req.name

    audit_log.info(
        "user_registered",
        extra={"user_id": user_id, "identifier": _mask(req.identifier)},
    )

    access_token = create_access_token({"sub": str(user_id)})
    refresh_token = create_refresh_token({"sub": str(user_id)})

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user_id,
        name=user_name,
        is_new_user=True,
    )


# =========================
# LOGIN
# =========================

@router.post("/login", response_model=TokenResponse)
async def login(req: LoginRequest, db: AsyncSession = Depends(get_db)):
    # Rate limiting on verification attempts
    await _check_otp_verify_rate(req.identifier)

    # Fetch all valid OTPs via stored function
    otp_rows = await _fn_get_valid_otps(db, req.identifier, "auth")

    # Verify OTP against stored HMAC-SHA256 hashes (constant-time comparison)
    matched_otp = None
    for row in otp_rows:
        if verify_otp(req.otp_code, row.otp_hash):
            matched_otp = row
            break

    if not matched_otp:
        raise HTTPException(status_code=400, detail="Invalid or expired OTP")

    await _clear_verify_rate(req.identifier)

    # Fetch user via stored function
    user_row = await _fn_get_user_by_identifier(db, req.identifier)
    if not user_row:
        raise HTTPException(status_code=404, detail="User not found. Please register first.")

    # Mark OTP as used via stored procedure
    await _sp_mark_otp_used(db, matched_otp.id)
    await db.commit()

    audit_log.info(
        "user_login",
        extra={"user_id": user_row.id, "identifier": _mask(req.identifier)},
    )

    access_token = create_access_token({"sub": str(user_row.id)})
    refresh_token = create_refresh_token({"sub": str(user_row.id)})

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user_row.id,
        name=user_row.name,
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
