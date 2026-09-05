from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from app.core.log_decorator import LoggedAPIRoute
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import asyncio
import json
import logging
from datetime import datetime, timedelta, timezone

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.config import settings
from app.models.user import User
from app.models.otp import OTP
from app.schemas.user import (
    UserUpdate, UserResponse,
    RequestContactChangeRequest, ConfirmContactChangeRequest,
)
from app.utils.storage import save_file, save_profile_image, delete_file
from app.services.cache_service import CacheService, USER_PROFILE_TTL
from app.services.user_data_export_service import build_user_data_export
from app.core.logging_config import audit_log
from app.core.security import generate_otp, hash_otp, verify_otp
# Re-use OTP delivery helpers from auth route
from app.api.routes.auth import (
    _send_email_otp, _send_sms_otp,
    is_email, _normalize_identifier,
    _sp_insert_otp, _fn_get_valid_otps, _sp_mark_otp_used,
    _mask,
)

router = APIRouter(route_class=LoggedAPIRoute)
logger = logging.getLogger(__name__)

_CONTACT_CHANGE_PURPOSE = "contact_change"
_CONTACT_CHANGE_CACHE_TTL = 15 * 60  # 15 minutes


@router.get("/me", response_model=UserResponse)
async def get_profile(current_user: User = Depends(get_current_user)):
    cache_key = f"user:{current_user.id}:profile"
    cached = await CacheService.get(cache_key)
    if cached is not None:
        return cached

    response = _user_to_response(current_user)
    await CacheService.set(cache_key, response, ttl=USER_PROFILE_TTL)
    return response


@router.get("/me/data-export")
async def export_my_data(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    HN-LEGAL-007 — APP access export for the authenticated owner only.

    Returns application/json attachment. Never accepts a client user_id.
    Does not log the export body or any PHI fields.
    """
    payload = await build_user_data_export(db, current_user)
    body = json.dumps(payload, default=str, ensure_ascii=False)
    filename = f"healthnest-data-export-{current_user.id}.json"
    audit_log.info(
        "user_data_exported",
        extra={
            "user_id": current_user.id,
            "schema_version": payload.get("export_schema_version"),
            "byte_length": len(body.encode("utf-8")),
        },
    )
    return Response(
        content=body.encode("utf-8"),
        media_type="application/json",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
        },
    )


@router.put("/me", response_model=UserResponse)
async def update_profile(
    updates: UserUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if updates.name is not None:
        current_user.name = updates.name
    if updates.age is not None:
        current_user.age = updates.age
    if updates.gender is not None:
        current_user.gender = updates.gender
    if updates.blood_group is not None:
        current_user.blood_group = updates.blood_group
    if updates.health_conditions is not None:
        # Store as JSON string — EncryptedText TypeDecorator encrypts automatically
        current_user.health_conditions = json.dumps(updates.health_conditions)
    if updates.allergies is not None:
        current_user.allergies = json.dumps(updates.allergies)
    if updates.lifestyle_preferences is not None:
        current_user.lifestyle_preferences = json.dumps(updates.lifestyle_preferences)
    if updates.fcm_token is not None:
        current_user.fcm_token = updates.fcm_token
    if updates.suburb is not None:
        current_user.suburb = updates.suburb
    if updates.city is not None:
        current_user.city = updates.city
    if updates.state is not None:
        current_user.state = updates.state
    if updates.postcode is not None:
        current_user.postcode = updates.postcode
    if updates.phone2 is not None:
        # Normalize and validate phone2 before storing
        normalized = _normalize_identifier(updates.phone2) if updates.phone2.strip() else None
        current_user.phone2 = normalized

    await db.commit()
    await db.refresh(current_user)

    # Invalidate cached profile
    await CacheService.delete(f"user:{current_user.id}:profile")

    audit_log.info("profile_updated", extra={"user_id": current_user.id})

    return _user_to_response(current_user)


_PHOTO_RATE_LIMIT  = 5     # max uploads per user
_PHOTO_RATE_WINDOW = 3600  # rolling 1-hour window (seconds)


@router.post("/me/photo")
async def upload_profile_photo(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Upload / replace the user's profile photo.

    Security controls:
      - Authentication required (JWT via get_current_user)
      - Rate limited: max 5 uploads per user per hour
      - File type: JPG / PNG only (magic-byte validated)
      - File size: max 2 MB
      - Path traversal protection in save_profile_image()
      - Old photo deleted from disk on replacement
      - Action recorded in audit log
    """
    # ── Rate limiting ────────────────────────────────────────────────────────
    rate_key = f"photo_upload:{current_user.id}"
    count = await CacheService.increment_counter(rate_key, ttl=_PHOTO_RATE_WINDOW)
    if count > _PHOTO_RATE_LIMIT:
        raise HTTPException(
            status_code=429,
            detail=f"Too many photo uploads. You may upload up to {_PHOTO_RATE_LIMIT} photos per hour.",
        )

    # ── Validate & save new file ─────────────────────────────────────────────
    try:
        rel_path = await save_profile_image(file, folder=f"profiles/{current_user.id}")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    # ── Delete previous photo (best-effort, non-fatal) ───────────────────────
    delete_file(current_user.profile_image_url)

    # ── Persist URL in DB ────────────────────────────────────────────────────
    current_user.profile_image_url = rel_path
    await db.commit()

    # Invalidate cached profile
    await CacheService.delete(f"user:{current_user.id}:profile")

    audit_log.info("profile_photo_uploaded", extra={
        "user_id": current_user.id,
        "file": rel_path,
        "size_bytes": file.size,
    })

    return {"profile_image_url": rel_path}


# ─────────────────── Contact Change (email / phone) ───────────────────

@router.post("/me/request-contact-change")
async def request_contact_change(
    req: RequestContactChangeRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Step 1 — Send OTP to the *new* email or phone number.
    The OTP is sent to the new contact so we can verify ownership.

    contact_type must be "email" or "phone".
    new_value    is the new email address or phone number (E.164 or AU/IN local format).
    """
    if req.contact_type not in ("email", "phone"):
        raise HTTPException(status_code=400, detail="contact_type must be 'email' or 'phone'")

    # Normalize identifier
    try:
        normalized = _normalize_identifier(req.new_value)
    except HTTPException as exc:
        raise exc

    # Validate type matches
    if req.contact_type == "email" and not is_email(normalized):
        raise HTTPException(status_code=400, detail="Provide a valid email address for contact_type='email'")
    if req.contact_type == "phone" and is_email(normalized):
        raise HTTPException(status_code=400, detail="Provide a valid phone number for contact_type='phone'")

    # Make sure the new value is not already used by another user
    if req.contact_type == "email":
        existing = await db.execute(
            select(User).where(User.email == normalized, User.id != current_user.id)
        )
        if existing.scalar_one_or_none():
            raise HTTPException(status_code=409, detail="This email is already registered with another account.")
    else:
        # Check both primary and secondary phone columns
        existing = await db.execute(
            select(User).where(
                ((User.phone == normalized) | (User.phone2 == normalized)),
                User.id != current_user.id,
            )
        )
        if existing.scalar_one_or_none():
            raise HTTPException(status_code=409, detail="This phone number is already registered with another account.")

    # Generate and store OTP
    otp_code = generate_otp()
    otp_hash = hash_otp(otp_code)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=settings.OTP_EXPIRY_MINUTES)
    await _sp_insert_otp(db, normalized, otp_code, otp_hash, _CONTACT_CHANGE_PURPOSE, expires_at)
    await db.commit()

    # Cache the pending new value so confirm can verify it wasn't tampered
    cache_key = f"contact_change:{current_user.id}:{req.contact_type}"
    await CacheService.set(cache_key, normalized, ttl=_CONTACT_CHANGE_CACHE_TTL)

    # Send OTP — run synchronous delivery in a thread to avoid blocking event loop
    if req.contact_type == "email":
        delivered, err = await asyncio.to_thread(_send_email_otp, normalized, otp_code)
        channel = "email"
    else:
        delivered, err = await asyncio.to_thread(_send_sms_otp, normalized, otp_code)
        channel = "sms"

    # Never log plaintext OTP — destination is masked; delivery status only.
    logger.info(
        "contact_change_otp user_id=%d type=%s target=%s delivered=%s",
        current_user.id, req.contact_type, _mask(normalized), delivered,
    )

    return {
        "message": f"Verification code sent to {_mask(normalized)} via {channel}.",
        "delivered": delivered,
        "channel": channel,
        "delivery_error": err if not delivered else None,
        "expires_in_minutes": settings.OTP_EXPIRY_MINUTES,
    }


@router.post("/me/confirm-contact-change", response_model=UserResponse)
async def confirm_contact_change(
    req: ConfirmContactChangeRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Step 2 — Verify OTP and apply the contact change.
    On success the user's email or phone is updated and the profile is returned.
    """
    if req.contact_type not in ("email", "phone"):
        raise HTTPException(status_code=400, detail="contact_type must be 'email' or 'phone'")

    try:
        normalized = _normalize_identifier(req.new_value)
    except HTTPException as exc:
        raise exc

    # Confirm the pending value matches what was originally requested
    cache_key = f"contact_change:{current_user.id}:{req.contact_type}"
    pending_value = await CacheService.get(cache_key)
    if pending_value is None:
        raise HTTPException(
            status_code=400,
            detail="No pending contact change request found. Please request a new OTP.",
        )
    if pending_value != normalized:
        raise HTTPException(
            status_code=400,
            detail="Contact value does not match the pending request.",
        )

    # Verify OTP
    rows = await _fn_get_valid_otps(db, normalized, _CONTACT_CHANGE_PURPOSE)
    if not rows:
        raise HTTPException(status_code=400, detail="OTP is invalid or has expired.")

    matched_row = None
    for row in rows:
        if verify_otp(req.otp_code, row.otp_hash):
            matched_row = row
            break

    if matched_row is None:
        raise HTTPException(status_code=400, detail="Incorrect OTP. Please try again.")

    # Mark OTP as used
    await _sp_mark_otp_used(db, matched_row.id)

    # Apply the contact update
    if req.contact_type == "email":
        current_user.email = normalized
        current_user.is_verified = True
    else:
        current_user.phone = normalized

    await db.commit()
    await db.refresh(current_user)

    # Clear pending cache
    await CacheService.delete(cache_key)
    # Invalidate profile cache
    await CacheService.delete(f"user:{current_user.id}:profile")

    audit_log.info(
        "contact_changed",
        extra={"user_id": current_user.id, "type": req.contact_type},
    )

    return _user_to_response(current_user)


@router.delete("/me")
async def delete_account(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Permanently delete the authenticated user's account and associated rows.

    Related tables use ON DELETE CASCADE. Uploaded profile photos are removed
    from disk. This is a hard delete (not a freeze), as required for Play
    account-deletion policy.
    """
    user_id = current_user.id
    delete_file(current_user.profile_image_url)

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    await db.delete(user)
    await db.commit()
    await CacheService.delete(f"user:{user_id}:profile")
    audit_log.info("account_deleted", extra={"user_id": user_id})
    return {"message": "Account and associated data deleted"}


# ─────────────────── helpers ───────────────────

def _user_to_response(user: User) -> dict:
    # health_conditions and allergies are decrypted by EncryptedText TypeDecorator
    def _parse_json(value):
        if not value:
            return []
        try:
            return json.loads(value)
        except (json.JSONDecodeError, TypeError):
            return []

    return {
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "phone": user.phone,
        "phone2": user.phone2,
        "age": user.age,
        "gender": user.gender,
        "blood_group": user.blood_group,
        "health_conditions": _parse_json(user.health_conditions),
        "allergies": _parse_json(user.allergies),
        "profile_image_url": user.profile_image_url,
        "suburb": user.suburb,
        "city": user.city,
        "state": user.state,
        "postcode": user.postcode,
        "is_verified": user.is_verified,
        "created_at": user.created_at,
    }
