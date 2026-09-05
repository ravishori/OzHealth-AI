"""
ePrescription API routes — FastAPI router.

Endpoints
─────────
  POST   /validate                   Validate a QR token against eRx Script Exchange (NPDS)
  GET    /                           List current user's validated ePrescriptions
  GET    /{id}                       Retrieve a single ePrescription in full detail
  DELETE /{id}                       Remove an ePrescription record
  POST   /extract-token              (utility) Extract token from an uploaded QR image

  POST   /{id}/save-to-records       Auto-save prescription to medical records
  POST   /{id}/refill-reminders      Add a per-medicine refill reminder
  GET    /{id}/refill-reminders      List all refill reminders for a prescription
  DELETE /{id}/refill-reminders/{r}  Remove a refill reminder

  POST   /{id}/interactions          Run drug-interaction AI check on this prescription
  POST   /{id}/share                 Share prescription with a family member
  GET    /{id}/shares                List family members this prescription is shared with
  DELETE /{id}/share/{s}             Revoke a share

Security
────────
  • Rate-limited: 20 validations per user per hour
  • Token hash (SHA-256) stored; raw token never logged or persisted
  • Replay protection: duplicate token_hash → 409 Conflict
  • All patient / prescriber fields encrypted at rest via EncryptedText

Logging
───────
  • INFO  → app.log   (request lifecycle, audit events)
  • ERROR → errors.log + developer email alert on 5xx
"""
from __future__ import annotations

import json
import logging
import traceback

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.exceptions import RateLimitError
from app.core.log_decorator import LoggedAPIRoute
from app.core.logging_config import audit_log
from app.models.eprescription import EPrescription, EPrescriptionRefillReminder, EPrescriptionShare
from app.models.family_member import FamilyMember
from app.models.user import User
from app.schemas.eprescription import (
    EPrescriptionListItem,
    EPrescriptionMedicine,
    EPrescriptionResponse,
    EPrescriptionValidateRequest,
    InteractionCheckResponse,
    RefillReminderCreate,
    RefillReminderResponse,
    ShareCreate,
    ShareResponse,
)
from app.services.cache_service import CacheService
from app.services.eprescription_service import (
    enrich_with_tga,
    extract_token_from_qr,
    hash_token,
    parse_date,
    validate_eprescription_token,
)

router = APIRouter(route_class=LoggedAPIRoute)
logger = logging.getLogger(__name__)

# ── Rate limiting ──────────────────────────────────────────────────────────────
_EP_RATE_LIMIT  = 20    # max validations per user per hour
_EP_RATE_WINDOW = 3600  # seconds


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _medicines_from_ep(ep: EPrescription) -> list[EPrescriptionMedicine]:
    """Deserialise the encrypted medicines JSON into schema objects."""
    if not ep.medicines:
        return []
    try:
        raw = ep.medicines if isinstance(ep.medicines, list) else json.loads(ep.medicines)
        return [EPrescriptionMedicine(**m) for m in (raw or [])]
    except Exception as exc:
        logger.warning("Could not deserialise medicines for ep_id=%s: %s", ep.id, exc)
        return []


def _to_response(ep: EPrescription) -> EPrescriptionResponse:
    return EPrescriptionResponse(
        id=ep.id,
        provider=ep.provider,
        status=ep.status,
        token_last4=ep.token_last4,
        patient_name=ep.patient_name,
        prescriber_name=ep.prescriber_name,
        prescriber_provider_number=ep.prescriber_provider_number,
        prescriber_practice=ep.prescriber_practice,
        medicines=_medicines_from_ep(ep),
        prescription_date=ep.prescription_date,
        expiry_date=ep.expiry_date,
        tga_enriched=ep.tga_enriched,
        saved_to_records=ep.saved_to_records or False,
        created_at=ep.created_at,
    )


def _to_list_item(ep: EPrescription) -> EPrescriptionListItem:
    count = 0
    if ep.medicines:
        try:
            raw = ep.medicines if isinstance(ep.medicines, list) else json.loads(ep.medicines)
            count = len(raw or [])
        except Exception:
            pass
    return EPrescriptionListItem(
        id=ep.id,
        provider=ep.provider,
        status=ep.status,
        token_last4=ep.token_last4,
        patient_name=ep.patient_name,
        prescriber_name=ep.prescriber_name,
        medicine_count=count,
        prescription_date=ep.prescription_date,
        saved_to_records=ep.saved_to_records or False,
        created_at=ep.created_at,
    )


async def _get_ep_for_user(ep_id: int, user_id: int, db: AsyncSession) -> EPrescription:
    """Fetch an ePrescription owned by this user; raise 404 if not found."""
    result = await db.execute(
        select(EPrescription).where(
            EPrescription.id      == ep_id,
            EPrescription.user_id == user_id,
        )
    )
    ep = result.scalar_one_or_none()
    if not ep:
        raise HTTPException(status_code=404, detail="ePrescription not found.")
    return ep


# ─── Validate ─────────────────────────────────────────────────────────────────

@router.post("/validate", response_model=EPrescriptionResponse, status_code=201)
async def validate_eprescription(
    req: EPrescriptionValidateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Validate an ePrescription token against eRx Script Exchange (NPDS).

    Steps:
      1. Rate-limit check (20 / hour / user)
      2. Extract & clean token (strips URL wrapper if QR contains a URL)
      3. Hash token → replay-attack check (unique constraint)
      4. Call provider API (or mock in dev mode)
      5. Enrich medicines with TGA database
      6. Encrypt & persist to DB
      7. Return structured prescription data

    HTTP errors:
      400 — invalid / expired token
      409 — token already processed (replay)
      429 — rate limit exceeded
      502 — provider API error
      503 — provider auth failure
      504 — provider API timeout
    """
    # ── 1. Rate limit ─────────────────────────────────────────────────────────
    rate_key = f"ep:validate:{current_user.id}"
    try:
        count = await CacheService.increment_counter(rate_key, ttl=_EP_RATE_WINDOW)
        if count > _EP_RATE_LIMIT:
            raise RateLimitError(
                f"Too many ePrescription validations. Try again in 1 hour.",
                retry_after=_EP_RATE_WINDOW,
            )
    except RateLimitError:
        raise
    except Exception as exc:
        logger.warning("Rate-limit check failed (Redis?): %s", exc)

    # ── 2. Normalise token ────────────────────────────────────────────────────
    raw_token   = req.token.strip()
    clean_token = extract_token_from_qr(raw_token)
    token_hash  = hash_token(clean_token)
    token_last4 = clean_token[-4:] if len(clean_token) >= 4 else clean_token

    # ── 3. Replay protection ──────────────────────────────────────────────────
    existing = await db.execute(
        select(EPrescription).where(EPrescription.token_hash == token_hash)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=409,
            detail=(
                "This ePrescription has already been processed. "
                "Each token can only be used once."
            ),
        )

    # ── 4. Validate with provider ─────────────────────────────────────────────
    try:
        data = await validate_eprescription_token(
            token=clean_token,
            provider=req.provider,
        )
    except ValueError as exc:
        logger.info("ePrescription token rejected: %s", exc)
        raise HTTPException(status_code=400, detail=str(exc))
    except PermissionError as exc:
        logger.error("ePrescription provider auth error: %s", exc)
        raise HTTPException(status_code=503, detail=str(exc))
    except TimeoutError as exc:
        logger.warning("ePrescription provider timeout: %s", exc)
        raise HTTPException(status_code=504, detail=str(exc))
    except RuntimeError as exc:
        logger.error("ePrescription provider error: %s", exc, exc_info=True)
        raise HTTPException(status_code=502, detail=str(exc))
    except Exception as exc:
        logger.error(
            "Unexpected error validating ePrescription for user_id=%s: %s",
            current_user.id, exc, exc_info=True,
        )
        raise HTTPException(
            status_code=500,
            detail="An unexpected error occurred. Please try again.",
        )

    # ── 5. TGA enrichment ─────────────────────────────────────────────────────
    medicines    = data.get("medicines", [])
    tga_enriched = False
    if medicines:
        try:
            medicines    = await enrich_with_tga(medicines, db)
            tga_enriched = True
        except Exception as exc:
            logger.warning("TGA enrichment skipped (non-fatal): %s", exc)

    # ── 6. Persist (encrypted) ────────────────────────────────────────────────
    ep = EPrescription(
        user_id                  = current_user.id,
        token_hash               = token_hash,
        token_last4              = token_last4,
        provider                 = data.get("provider", req.provider),
        status                   = "validated",
        patient_name             = data.get("patient_name"),
        prescriber_name          = data.get("prescriber_name"),
        prescriber_provider_number = data.get("prescriber_provider_number"),
        prescriber_practice      = data.get("prescriber_practice"),
        medicines                = json.dumps(medicines),
        prescription_date        = parse_date(data.get("prescription_date")),
        expiry_date              = parse_date(data.get("expiry_date")),
        tga_enriched             = tga_enriched,
        saved_to_records         = False,
    )
    db.add(ep)
    await db.commit()
    await db.refresh(ep)

    audit_log.info(
        "eprescription_validated",
        extra={
            "user_id":        current_user.id,
            "ep_id":          ep.id,
            "provider":       ep.provider,
            "medicine_count": len(medicines),
            "tga_enriched":   tga_enriched,
        },
    )

    return _to_response(ep)


# ─── List / Detail / Delete ───────────────────────────────────────────────────

@router.get("/", response_model=list[EPrescriptionListItem])
async def list_eprescriptions(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return all ePrescriptions belonging to the current user, newest first."""
    result = await db.execute(
        select(EPrescription)
        .where(EPrescription.user_id == current_user.id)
        .order_by(EPrescription.created_at.desc())
    )
    eps = result.scalars().all()
    return [_to_list_item(ep) for ep in eps]


@router.get("/{ep_id}", response_model=EPrescriptionResponse)
async def get_eprescription(
    ep_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Return full detail for a single ePrescription owned by the current user."""
    ep = await _get_ep_for_user(ep_id, current_user.id, db)
    return _to_response(ep)


@router.delete("/{ep_id}", status_code=204)
async def delete_eprescription(
    ep_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Permanently delete an ePrescription record.
    Returns 204 No Content on success.
    """
    ep = await _get_ep_for_user(ep_id, current_user.id, db)
    await db.delete(ep)
    await db.commit()

    audit_log.info(
        "eprescription_deleted",
        extra={"user_id": current_user.id, "ep_id": ep_id},
    )


# ─── Auto-save to records ─────────────────────────────────────────────────────

@router.post("/{ep_id}/save-to-records")
async def save_to_records(
    ep_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Mark this ePrescription as saved to the user's medical records.
    Idempotent — calling again when already saved returns the same 200.
    """
    ep = await _get_ep_for_user(ep_id, current_user.id, db)

    if not ep.saved_to_records:
        ep.saved_to_records = True
        await db.commit()
        await db.refresh(ep)

        audit_log.info(
            "eprescription_saved_to_records",
            extra={"user_id": current_user.id, "ep_id": ep_id},
        )
        logger.info("ePrescription %s saved to records by user %s", ep_id, current_user.id)

    return {
        "id":               ep.id,
        "saved_to_records": ep.saved_to_records,
        "message":          "Prescription saved to your medical records.",
    }


@router.delete("/{ep_id}/save-to-records", status_code=200)
async def unsave_from_records(
    ep_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Remove the saved-to-records flag."""
    ep = await _get_ep_for_user(ep_id, current_user.id, db)
    ep.saved_to_records = False
    await db.commit()
    return {"id": ep.id, "saved_to_records": False}


# ─── Refill reminders ─────────────────────────────────────────────────────────

@router.post("/{ep_id}/refill-reminders", response_model=RefillReminderResponse, status_code=201)
async def add_refill_reminder(
    ep_id: int,
    req: RefillReminderCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Add a refill reminder for a specific medicine in this prescription."""
    # Confirm ep belongs to user
    ep = await _get_ep_for_user(ep_id, current_user.id, db)

    reminder = EPrescriptionRefillReminder(
        ep_id         = ep.id,
        user_id       = current_user.id,
        medicine_name = req.medicine_name.strip(),
        refill_date   = req.refill_date,
        note          = req.note,
        is_notified   = False,
    )
    db.add(reminder)
    await db.commit()
    await db.refresh(reminder)

    audit_log.info(
        "ep_refill_reminder_created",
        extra={
            "user_id":       current_user.id,
            "ep_id":         ep_id,
            "medicine_name": reminder.medicine_name,
            "refill_date":   str(reminder.refill_date),
        },
    )
    return reminder


@router.get("/{ep_id}/refill-reminders", response_model=list[RefillReminderResponse])
async def list_refill_reminders(
    ep_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List all refill reminders for a prescription (newest first)."""
    await _get_ep_for_user(ep_id, current_user.id, db)  # ownership check

    result = await db.execute(
        select(EPrescriptionRefillReminder)
        .where(
            EPrescriptionRefillReminder.ep_id   == ep_id,
            EPrescriptionRefillReminder.user_id == current_user.id,
        )
        .order_by(EPrescriptionRefillReminder.refill_date.asc())
    )
    return result.scalars().all()


@router.delete("/{ep_id}/refill-reminders/{reminder_id}", status_code=204)
async def delete_refill_reminder(
    ep_id: int,
    reminder_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Remove a refill reminder."""
    await _get_ep_for_user(ep_id, current_user.id, db)

    result = await db.execute(
        select(EPrescriptionRefillReminder).where(
            EPrescriptionRefillReminder.id      == reminder_id,
            EPrescriptionRefillReminder.ep_id   == ep_id,
            EPrescriptionRefillReminder.user_id == current_user.id,
        )
    )
    reminder = result.scalar_one_or_none()
    if not reminder:
        raise HTTPException(status_code=404, detail="Refill reminder not found.")
    await db.delete(reminder)
    await db.commit()


# ─── Drug interaction check ───────────────────────────────────────────────────

@router.post("/{ep_id}/interactions", response_model=InteractionCheckResponse)
async def check_ep_interactions(
    ep_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Run an AI drug-interaction check on all medicines in this ePrescription.
    Requires at least 2 medicines; returns the full interaction analysis.
    """
    from app.services.ai_service import check_drug_interactions, detect_duplicate_medicines

    ep = await _get_ep_for_user(ep_id, current_user.id, db)
    meds_raw = _medicines_from_ep(ep)
    if len(meds_raw) < 2:
        raise HTTPException(
            status_code=400,
            detail="At least 2 medicines are required to check for interactions.",
        )

    medicine_names = [m.name for m in meds_raw]

    user_context: dict = {}
    if current_user.age:
        user_context["age"] = current_user.age

    try:
        interaction_result = await check_drug_interactions(medicine_names, user_context)
        duplicate_result   = await detect_duplicate_medicines(medicine_names)
    except Exception as exc:
        logger.error(
            "Interaction check failed for ep_id=%s user_id=%s: %s",
            ep_id, current_user.id, exc, exc_info=True,
        )
        raise HTTPException(
            status_code=502,
            detail="AI interaction check failed. Please try again.",
        )

    audit_log.info(
        "ep_interaction_checked",
        extra={"user_id": current_user.id, "ep_id": ep_id, "medicine_count": len(medicine_names)},
    )
    return InteractionCheckResponse(
        ep_id=ep_id,
        medicines_checked=medicine_names,
        interaction_analysis=interaction_result,
        duplicate_check=duplicate_result,
    )


# ─── Share with family ────────────────────────────────────────────────────────

@router.post("/{ep_id}/share", response_model=ShareResponse, status_code=201)
async def share_with_family(
    ep_id: int,
    req: ShareCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Share this ePrescription with one of the user's family members."""
    ep = await _get_ep_for_user(ep_id, current_user.id, db)

    # Confirm the family member belongs to this user
    fm_result = await db.execute(
        select(FamilyMember).where(
            FamilyMember.id      == req.family_member_id,
            FamilyMember.user_id == current_user.id,
            FamilyMember.is_active == True,
        )
    )
    fm = fm_result.scalar_one_or_none()
    if not fm:
        raise HTTPException(
            status_code=404,
            detail="Family member not found.",
        )

    # Idempotency — return existing share if already shared
    existing_result = await db.execute(
        select(EPrescriptionShare).where(
            EPrescriptionShare.ep_id            == ep_id,
            EPrescriptionShare.family_member_id == req.family_member_id,
        )
    )
    existing_share = existing_result.scalar_one_or_none()
    if existing_share:
        return ShareResponse(
            id=existing_share.id,
            ep_id=existing_share.ep_id,
            family_member_id=existing_share.family_member_id,
            family_member_name=existing_share.family_member_name,
            shared_at=existing_share.shared_at,
        )

    share = EPrescriptionShare(
        ep_id              = ep.id,
        owner_user_id      = current_user.id,
        family_member_id   = req.family_member_id,
        family_member_name = fm.name,
    )
    db.add(share)
    await db.commit()
    await db.refresh(share)

    audit_log.info(
        "eprescription_shared",
        extra={
            "user_id":          current_user.id,
            "ep_id":            ep_id,
            "family_member_id": req.family_member_id,
        },
    )
    return share


@router.get("/{ep_id}/shares", response_model=list[ShareResponse])
async def get_shares(
    ep_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List all family members this prescription has been shared with."""
    await _get_ep_for_user(ep_id, current_user.id, db)

    result = await db.execute(
        select(EPrescriptionShare).where(
            EPrescriptionShare.ep_id          == ep_id,
            EPrescriptionShare.owner_user_id  == current_user.id,
        )
    )
    return result.scalars().all()


@router.delete("/{ep_id}/share/{share_id}", status_code=204)
async def revoke_share(
    ep_id: int,
    share_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Revoke access to this prescription for a family member."""
    result = await db.execute(
        select(EPrescriptionShare).where(
            EPrescriptionShare.id            == share_id,
            EPrescriptionShare.ep_id         == ep_id,
            EPrescriptionShare.owner_user_id == current_user.id,
        )
    )
    share = result.scalar_one_or_none()
    if not share:
        raise HTTPException(status_code=404, detail="Share not found.")
    await db.delete(share)
    await db.commit()

    audit_log.info(
        "eprescription_share_revoked",
        extra={"user_id": current_user.id, "ep_id": ep_id, "share_id": share_id},
    )


# ─── Extract token from image ─────────────────────────────────────────────────

@router.post("/extract-token")
async def extract_token_from_image(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    """
    Utility endpoint: upload an image (JPG/PNG) or PDF containing an
    ePrescription QR code.  Backend decodes the QR and returns the raw token
    string so the Flutter app can call /validate without needing local QR libs.

    Currently supported formats: JPEG, PNG.
    Returns: { "token": "...", "provider": "erx" }
    """
    import io
    from PIL import Image
    from pyzbar.pyzbar import decode as pyzbar_decode

    ALLOWED_MIMES = {"image/jpeg", "image/png", "image/jpg"}
    if file.content_type not in ALLOWED_MIMES:
        raise HTTPException(
            status_code=400,
            detail="Only JPEG and PNG images are supported for QR extraction.",
        )

    content = await file.read()
    if len(content) > 5 * 1024 * 1024:  # 5 MB limit
        raise HTTPException(status_code=400, detail="Image file too large (max 5 MB).")

    try:
        img      = Image.open(io.BytesIO(content))
        barcodes = pyzbar_decode(img)
    except Exception as exc:
        logger.warning("QR decode error for user_id=%s: %s", current_user.id, exc)
        raise HTTPException(
            status_code=422,
            detail="Could not decode the image. Ensure it contains a clear QR code.",
        )

    if not barcodes:
        raise HTTPException(
            status_code=404,
            detail="No QR code found in the uploaded image.",
        )

    raw_qr   = barcodes[0].data.decode("utf-8", errors="replace")
    token    = extract_token_from_qr(raw_qr)
    provider = _detect_provider(raw_qr)

    audit_log.info(
        "eprescription_qr_extracted",
        extra={"user_id": current_user.id, "provider": provider},
    )
    return {"token": token, "provider": provider}


def _detect_provider(raw_qr: str) -> str:
    """Always returns 'erx'. MediSecure is discontinued (2024)."""
    return "erx"
