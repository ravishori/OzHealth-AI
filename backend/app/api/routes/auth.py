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
from app.core.deps import get_current_user, token_version_matches
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


def _user_token_version(user) -> int:
    return int(getattr(user, "token_version", 0) or 0)

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
    result = await db.execute(
        text("SELECT * FROM fn_get_valid_otps(:identifier, :purpose)"),
        {"identifier": identifier, "purpose": purpose},
    )
    return result.fetchall()


@log_fn
async def _sp_mark_otp_used(db: AsyncSession, otp_id: int) -> None:
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
    result = await db.execute(
        text("SELECT * FROM fn_get_user_by_identifier(:identifier)"),
        {"identifier": identifier},
    )
    return result.fetchone()

router = APIRouter(route_class=LoggedAPIRoute)
logger = logging.getLogger(__name__)


# =========================
# Identifier helpers
# =========================

def is_email(identifier: str) -> bool:
    return "@" in identifier and "." in identifier.split("@")[-1]


def _normalize_phone(raw: str) -> str | None:
    """
    Normalize a phone number to E.164 format (+<country_code><number>).

    Handles:
    - Already E.164:       +61412345678   ->  +61412345678
    - Australian local:    0412345678     ->  +61412345678
    - Indian 10-digit:     9876543210     ->  +919876543210
    - Spaces/dashes:       +61 4XX XXX    ->  +614XXXXXXXX
    Returns None for unrecognisable formats.
    """
    # Strip whitespace, dashes, parentheses, dots
    cleaned = re.sub(r"[\s\-\.\(\)]", "", raw)

    # Already E.164 (+<7-15 digits>)
    if re.match(r"^\+\d{7,15}$", cleaned):
        return cleaned

    # Digits only from here
    digits_only = re.sub(r"\D", "", cleaned)
    if not digits_only:
        return None

    # Australian local 10-digit: starts with 0 (mobile 04XX, landline 02/03/07/08)
    if digits_only.startswith("0") and len(digits_only) == 10:
        return f"+61{digits_only[1:]}"

    # Indian 10-digit mobile: starts with 6, 7, 8, or 9
    if re.match(r"^[6-9]\d{9}$", digits_only):
        return f"+91{digits_only}"

    # Long digit string without +  — assume user omitted the leading +
    if len(digits_only) >= 10:
        return f"+{digits_only}"

    return None


def is_phone(identifier: str) -> bool:
    return _normalize_phone(identifier) is not None


def _normalize_identifier(raw: str) -> str:
    """Normalize email (lowercase) or phone (E.164). Raises 400 on bad phone format."""
    s = raw.strip()
    if is_email(s):
        return s.lower()
    normalized = _normalize_phone(s)
    if normalized is None:
        raise HTTPException(
            status_code=400,
            detail=(
                "Invalid phone number. Please include your country code, "
                "e.g. +61412345678 (Australia) or +919876543210 (India)."
            ),
        )
    return normalized


def _mask(identifier: str) -> str:
    """Mask identifier for safe logging."""
    return identifier[:4] + "***" if len(identifier) > 4 else "****"


# =========================
# Rate limiting helpers
# =========================

async def _check_otp_send_rate(identifier: str):
    key = f"otp_rate:send:{identifier}"
    count = await CacheService.increment_counter(key, ttl=settings.OTP_SEND_WINDOW)
    if count > settings.OTP_SEND_LIMIT:
        retry_after = await CacheService.get_ttl(key)
        raise RateLimitError(
            f"Too many OTP requests. Try again in {retry_after} seconds.",
            retry_after=retry_after,
        )


async def _check_otp_verify_rate(identifier: str):
    key = f"otp_rate:verify:{identifier}"
    count = await CacheService.increment_counter(key, ttl=settings.OTP_VERIFY_WINDOW)
    if count > settings.OTP_VERIFY_LIMIT:
        retry_after = await CacheService.get_ttl(key)
        raise RateLimitError(
            f"Too many failed attempts. Try again in {retry_after} seconds.",
            retry_after=retry_after,
        )


async def _clear_verify_rate(identifier: str):
    await CacheService.delete(f"otp_rate:verify:{identifier}")


# =========================
# Send Email OTP
# =========================

def _send_email_otp(email: str, otp: str) -> tuple[bool, str]:
    """
    Send OTP via SMTP (Gmail or any STARTTLS server).
    Returns (success, error_detail).
    Designed to run in asyncio.to_thread — never blocks the event loop.
    """
    import smtplib
    import time
    from email.mime.multipart import MIMEMultipart
    from email.mime.text import MIMEText as MIMETextPart

    if not settings.SMTP_EMAIL:
        return False, "SMTP_EMAIL not set in .env"
    if not settings.SMTP_PASSWORD:
        return False, (
            "SMTP_PASSWORD not set. For Gmail use an App Password: "
            "https://myaccount.google.com/apppasswords"
        )

    subject = f"Your {settings.APP_NAME} Verification Code"
    html_body = f"""<!DOCTYPE html>
<html>
<body style="font-family:Arial,sans-serif;background:#f4f4f4;margin:0;padding:20px;">
  <div style="max-width:480px;margin:0 auto;background:#fff;border-radius:8px;overflow:hidden;">
    <div style="background:#00897B;padding:24px;text-align:center;">
      <h1 style="color:#fff;margin:0;font-size:22px;">{settings.APP_NAME}</h1>
    </div>
    <div style="padding:32px 24px;">
      <h2 style="color:#333;margin:0 0 8px;">Verification Code</h2>
      <p style="color:#666;margin:0 0 24px;">
        Use the code below to verify your identity.
        It expires in <strong>{settings.OTP_EXPIRY_MINUTES} minutes</strong>.
      </p>
      <div style="background:#e8f5e9;border-radius:8px;padding:20px;text-align:center;margin-bottom:24px;">
        <span style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#00897B;">{otp}</span>
      </div>
      <p style="color:#999;font-size:12px;">
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
        f"Your {settings.APP_NAME} OTP: {otp}\n"
        f"Expires in {settings.OTP_EXPIRY_MINUTES} minutes. Never share this code.",
        "plain",
    ))
    msg.attach(MIMETextPart(html_body, "html"))

    last_error = "Unknown error"
    for attempt in range(1, 3):
        try:
            with smtplib.SMTP(settings.SMTP_SERVER, settings.SMTP_PORT, timeout=8) as server:
                server.ehlo()
                server.starttls()
                server.ehlo()
                server.login(settings.SMTP_EMAIL, settings.SMTP_PASSWORD)
                server.sendmail(settings.SMTP_EMAIL, email, msg.as_string())
            logger.info("OTP email sent to %s (attempt %d)", _mask(email), attempt)
            return True, ""
        except smtplib.SMTPAuthenticationError:
            last_error = (
                "Gmail authentication failed. "
                "You must use an App Password (not your Gmail password). "
                "Generate one at https://myaccount.google.com/apppasswords"
            )
            logger.error("SMTP auth failed for %s — check App Password config", _mask(email))
            break  # No retry on auth failures
        except smtplib.SMTPRecipientsRefused:
            last_error = f"Email address refused by server: {email}"
            logger.error("SMTP recipient refused: %s", _mask(email))
            break
        except smtplib.SMTPConnectError as exc:
            last_error = f"Cannot connect to SMTP server {settings.SMTP_SERVER}:{settings.SMTP_PORT}: {exc}"
            logger.warning("SMTP connect error (attempt %d/2): %s", attempt, exc)
            if attempt < 2:
                time.sleep(2)
        except Exception as exc:
            last_error = str(exc)
            logger.warning("Email send attempt %d/2 failed for %s: %s", attempt, _mask(email), exc)
            if attempt < 2:
                time.sleep(1)

    logger.error("All email attempts failed for %s: %s", _mask(email), last_error)
    return False, last_error


# =========================
# Send SMS OTP via Twilio
# =========================

def _send_sms_otp(phone: str, otp: str) -> tuple[bool, str]:
    """
    Send OTP via Twilio SMS. Phone MUST be in E.164 format (+<country_code><number>).
    Returns (success, error_detail).
    Designed to run in asyncio.to_thread — never blocks the event loop.
    """
    if not settings.TWILIO_ACCOUNT_SID:
        return False, "TWILIO_ACCOUNT_SID not set in .env"
    if not settings.TWILIO_AUTH_TOKEN:
        return False, "TWILIO_AUTH_TOKEN not set in .env"
    if not settings.TWILIO_PHONE_NUMBER:
        return False, "TWILIO_PHONE_NUMBER not set in .env"

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
        logger.info("SMS sent SID=%s to %s", message.sid, _mask(phone))
        return True, ""

    except Exception as exc:
        err_str = str(exc)
        # Map Twilio error codes to actionable messages
        if "21211" in err_str:
            detail = (
                f"Invalid 'To' phone number '{phone}'. "
                "Ensure the number includes the country code in E.164 format "
                "(e.g. +61412345678 for Australia, +919876543210 for India)."
            )
        elif "21608" in err_str:
            detail = (
                "Twilio trial account: the destination number is not verified. "
                "Add it at: https://console.twilio.com/us1/develop/phone-numbers/verified-caller-ids"
            )
        elif "21614" in err_str:
            detail = (
                f"Phone number '{phone}' is not a mobile/SMS-capable number."
            )
        elif "20003" in err_str or "Authentication Error" in err_str.lower():
            detail = (
                "Twilio authentication failed. "
                "Check TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN in your .env file."
            )
        elif "20404" in err_str:
            detail = "Twilio account not found. Verify TWILIO_ACCOUNT_SID is correct."
        else:
            detail = f"SMS delivery failed: {err_str[:300]}"

        logger.error("SMS send failed for %s: %s", _mask(phone), detail)
        return False, detail


# =========================
# SEND OTP
# =========================

@router.post("/send-otp")
async def send_otp(req: SendOTPRequest, db: AsyncSession = Depends(get_db)):
    """Send an OTP to the given email or phone."""
    identifier = _normalize_identifier(req.identifier)

    # For login, reject if no account exists — don't waste an OTP delivery
    if req.purpose == "auth":
        existing = await _fn_get_user_by_identifier(db, identifier)
        if existing is None:
            raise HTTPException(
                status_code=404,
                detail="No account found for this email or phone. Please register first.",
            )

    # Rate limiting
    await _check_otp_send_rate(identifier)

    otp_code = generate_otp()
    otp_hash = hash_otp(otp_code)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=settings.OTP_EXPIRY_MINUTES)

    await _sp_insert_otp(
        db,
        identifier=identifier,
        otp_code=otp_code,
        otp_hash=otp_hash,
        purpose=req.purpose,
        expires_at=expires_at,
    )
    await db.commit()

    # Send via thread pool (SMTP / Twilio are blocking I/O)
    sent = False
    delivery_error = ""
    channel = ""

    if is_email(identifier):
        channel = "email"
        sent, delivery_error = await asyncio.to_thread(_send_email_otp, identifier, otp_code)
    else:
        channel = "sms"
        sent, delivery_error = await asyncio.to_thread(_send_sms_otp, identifier, otp_code)

    # Never log plaintext OTP (including DEBUG). Masked identifier + delivery only.
    if settings.DEBUG:
        logger.info(
            "[DEV OTP] identifier=%s  purpose=%s  delivered=%s  expires=%s",
            _mask(identifier), req.purpose, sent,
            expires_at.strftime("%H:%M:%S UTC"),
        )

    # Log delivery failures to DB (always) and email alert (production only)
    if not sent:
        from app.services.alert_service import send_alert_email, log_error_to_db

        await log_error_to_db(
            source="backend",
            severity="error",
            error_type=f"OTPDeliveryFailure:{channel.upper()}",
            message=delivery_error,
            context=f"send_otp:{channel}",
            platform="server",
        )
        if not settings.DEBUG:
            await send_alert_email(
                subject=f"OTP Delivery Failure ({channel.upper()})",
                source="backend",
                error_type=f"OTPDeliveryFailure:{channel.upper()}",
                message=delivery_error,
                extra={
                    "identifier": _mask(identifier),
                    "channel": channel,
                    "purpose": req.purpose,
                },
            )
            raise HTTPException(
                status_code=502,
                detail="Something went wrong. Please try again later.",
            )

    audit_log.info(
        "otp_sent",
        extra={
            "identifier": _mask(identifier),
            "purpose": req.purpose,
            "channel": channel,
            "delivered": sent,
        },
    )

    response: dict = {
        "message": f"OTP sent to your {channel}." if sent else "OTP generated (dev mode — check server logs).",
        "expires_in_minutes": settings.OTP_EXPIRY_MINUTES,
        "channel": channel,
        "delivered": sent,
    }
    # In dev mode expose delivery errors to help fix config issues
    if settings.DEBUG and delivery_error:
        response["_dev_error"] = delivery_error

    return response


# =========================
# VERIFY OTP (standalone)
# =========================

@router.post("/verify-otp")
async def verify_otp_check(req: VerifyOTPRequest, db: AsyncSession = Depends(get_db)):
    """Pre-validate an OTP without consuming it or creating a session."""
    identifier = _normalize_identifier(req.identifier)
    await _check_otp_verify_rate(identifier)

    otp_rows = await _fn_get_valid_otps(db, identifier, req.purpose)
    for row in otp_rows:
        if verify_otp(req.otp_code, row.otp_hash):
            await _clear_verify_rate(identifier)
            audit_log.info(
                "otp_pre_verified",
                extra={"identifier": _mask(identifier), "purpose": req.purpose},
            )
            return {"valid": True, "message": "OTP verified successfully"}

    raise HTTPException(
        status_code=400,
        detail="Invalid or expired OTP. Please check the code and try again.",
    )


# =========================
# REGISTER
# =========================

@router.post("/register", response_model=TokenResponse)
async def register(req: RegisterRequest, db: AsyncSession = Depends(get_db)):
    identifier = _normalize_identifier(req.identifier)
    await _check_otp_verify_rate(identifier)

    otp_rows = await _fn_get_valid_otps(db, identifier, "register")
    matched_otp = None
    for row in otp_rows:
        if verify_otp(req.otp_code, row.otp_hash):
            matched_otp = row
            break

    if not matched_otp:
        raise HTTPException(
            status_code=400,
            detail="Invalid or expired OTP. Please request a new code and try again.",
        )

    await _clear_verify_rate(identifier)

    try:
        user_row = await _sp_insert_user(
            db,
            name=req.name,
            email=identifier if is_email(identifier) else None,
            phone=identifier if not is_email(identifier) else None,
            age=req.age,
            gender=req.gender,
            blood_group=req.blood_group,
        )
    except Exception as exc:
        err_str = str(exc)
        if "23505" in err_str or "already exists" in err_str.lower():
            raise HTTPException(
                status_code=400,
                detail="An account with this email/phone already exists. Please login instead.",
            )
        logger.error("User creation error: %s", exc, exc_info=True)
        raise HTTPException(status_code=500, detail="Registration failed. Please try again later.")

    await _sp_mark_otp_used(db, matched_otp.id)
    await db.commit()

    audit_log.info(
        "user_registered",
        extra={"user_id": user_row.id, "identifier": _mask(identifier)},
    )

    tv = _user_token_version(user_row)
    result = await db.execute(select(User).where(User.id == int(user_row.id)))
    orm_user = result.scalar_one_or_none()
    if orm_user is not None:
        tv = _user_token_version(orm_user)

    access_token = create_access_token(
        {"sub": str(user_row.id)},
        token_version=tv,
    )
    refresh_token = create_refresh_token(
        {"sub": str(user_row.id)},
        token_version=tv,
    )

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user_id=user_row.id,
        name=req.name,
        is_new_user=True,
    )


# =========================
# LOGIN
# =========================

@router.post("/login", response_model=TokenResponse)
async def login(req: LoginRequest, db: AsyncSession = Depends(get_db)):
    identifier = _normalize_identifier(req.identifier)
    await _check_otp_verify_rate(identifier)

    otp_rows = await _fn_get_valid_otps(db, identifier, "auth")
    matched_otp = None
    for row in otp_rows:
        if verify_otp(req.otp_code, row.otp_hash):
            matched_otp = row
            break

    if not matched_otp:
        raise HTTPException(
            status_code=400,
            detail="Invalid or expired OTP. Please request a new code and try again.",
        )

    await _clear_verify_rate(identifier)

    user_row = await _fn_get_user_by_identifier(db, identifier)
    if not user_row:
        raise HTTPException(
            status_code=404,
            detail="No account found for this email/phone. Please register first.",
        )

    await _sp_mark_otp_used(db, matched_otp.id)
    await db.commit()

    audit_log.info(
        "user_login",
        extra={"user_id": user_row.id, "identifier": _mask(identifier)},
    )

    # Prefer ORM token_version when SP row omits the column
    tv = _user_token_version(user_row)
    result = await db.execute(select(User).where(User.id == int(user_row.id)))
    orm_user = result.scalar_one_or_none()
    if orm_user is not None:
        tv = _user_token_version(orm_user)

    access_token = create_access_token(
        {"sub": str(user_row.id)},
        token_version=tv,
    )
    refresh_token = create_refresh_token(
        {"sub": str(user_row.id)},
        token_version=tv,
    )

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
        raise HTTPException(status_code=401, detail="Invalid refresh token. Please login again.")

    result = await db.execute(select(User).where(User.id == int(user_id)))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not token_version_matches(payload, user):
        raise HTTPException(
            status_code=401,
            detail="Session has been revoked. Please login again.",
        )

    tv = _user_token_version(user)
    access_token = create_access_token({"sub": str(user.id)}, token_version=tv)
    new_refresh_token = create_refresh_token({"sub": str(user.id)}, token_version=tv)

    return TokenResponse(
        access_token=access_token,
        refresh_token=new_refresh_token,
        user_id=user.id,
        name=user.name,
    )


# =========================
# LOGOUT (HN-AUTH-007)
# =========================

@router.post("/logout")
async def logout(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Invalidate this user's JWT session by bumping ``token_version``.

    All access and refresh tokens issued with the previous version are rejected
    immediately on the next validation/refresh. Does not affect other users.
    """
    current_user.token_version = _user_token_version(current_user) + 1
    await db.commit()
    audit_log.info(
        "user_logout",
        extra={"user_id": current_user.id},
    )
    return {"message": "Logged out"}
