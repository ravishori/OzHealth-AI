"""
Lab Report Analyzer — HN-FUTURE-002

POST /api/v1/lab-analysis/analyze              (upload + extract — unconfirmed)
POST /api/v1/lab-analysis/analyze-record/{id}  (re-extract existing record)
POST /api/v1/lab-analysis/confirm/{id}         (user confirmation gate)
POST /api/v1/lab-analysis/reject/{id}          (discard unconfirmed extraction)

ANALYZED ≠ VERIFIED. Extraction is stored as a draft until the user confirms
they reviewed it against the original report.
"""
from __future__ import annotations

import io
import json
import logging
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.datastructures import Headers

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.log_decorator import LoggedAPIRoute
from app.models.family_member import FamilyMember
from app.models.medical_record import MedicalRecord
from app.models.user import User
from app.services.ai_service import analyze_lab_report
from app.services.ocr_confidence import build_ocr_confidence_payload, normalize_confidence
from app.services.ocr_provider import get_ocr_provider
from app.utils.storage import (
    read_medical_record_bytes,
    save_encrypted_medical_file,
)

router = APIRouter(route_class=LoggedAPIRoute)
logger = logging.getLogger(__name__)

ALLOWED_EXTS = {"pdf", "jpg", "jpeg", "png", "heic"}
ALLOWED_MIME = {
    "image/jpeg",
    "image/jpg",
    "image/png",
    "image/heic",
    "application/pdf",
    "application/x-pdf",
    "application/octet-stream",
}
_JPEG = b"\xff\xd8\xff"
_PNG = b"\x89PNG\r\n\x1a\n"
_PDF = b"%PDF"
MAX_BYTES = 20 * 1024 * 1024


async def _require_owned_active_family_member(
    db: AsyncSession,
    family_member_id: int,
    user_id: int,
) -> FamilyMember:
    """Authoritative ownership check — 404 for missing/inactive/cross-user."""
    result = await db.execute(
        select(FamilyMember).where(
            FamilyMember.id == family_member_id,
            FamilyMember.user_id == user_id,
            FamilyMember.is_active == True,  # noqa: E712
        )
    )
    member = result.scalar_one_or_none()
    if not member:
        raise HTTPException(status_code=404, detail="Family member not found")
    return member


def _safe_ext(filename: Optional[str]) -> str:
    name = Path(filename or "upload.bin").name.replace("\\", "/").split("/")[-1]
    if "." not in name:
        raise HTTPException(status_code=400, detail="File must have an extension")
    ext = name.rsplit(".", 1)[-1].lower()
    if ext not in ALLOWED_EXTS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type .{ext}. Allowed: {sorted(ALLOWED_EXTS)}",
        )
    return ext


def _validate_magic(ext: str, content: bytes) -> None:
    if len(content) == 0:
        raise HTTPException(status_code=400, detail="Uploaded file is empty")
    if len(content) < 8:
        raise HTTPException(status_code=400, detail="File is empty or too small")
    if ext in ("jpg", "jpeg") and content[:3] != _JPEG:
        raise HTTPException(status_code=400, detail="Content is not a valid JPEG")
    if ext == "png" and content[:8] != _PNG:
        raise HTTPException(status_code=400, detail="Content is not a valid PNG")
    if ext == "pdf" and content[:4] != _PDF:
        raise HTTPException(status_code=400, detail="Content is not a valid PDF")
    # HEIC: extension-gated only (no portable magic check here)


def _pack_notes(analysis: dict, *, user_confirmed: bool) -> str:
    payload = {
        "kind": "lab_analysis_draft",
        "user_confirmed": user_confirmed,
        "review_required": not user_confirmed,
        "is_clinician_verified": False,
        "confirmed_at": (
            datetime.now(timezone.utc).isoformat() if user_confirmed else None
        ),
        "analysis": analysis,
    }
    return json.dumps(payload)


def _unpack_notes(notes: Optional[str]) -> Optional[dict]:
    if not notes or not str(notes).strip():
        return None
    try:
        data = json.loads(notes)
    except (TypeError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


async def _ocr_bytes(content: bytes, ext: str) -> tuple[str, dict[str, Any]]:
    """Run OCR on plaintext bytes via a temporary file (deleted after)."""
    fd, tmp = tempfile.mkstemp(prefix="lab_ocr_", suffix=f".{ext}")
    os.close(fd)
    path = Path(tmp)
    try:
        path.write_bytes(content)
        result = await get_ocr_provider().extract(path)
        conf_payload = build_ocr_confidence_payload(
            result.confidence,
            available=bool(result.available),
        )
        return (result.text or ""), conf_payload
    finally:
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass


async def _ocr_record_file(rel_path: str, file_type: Optional[str]) -> tuple[str, dict]:
    try:
        plaintext = read_medical_record_bytes(rel_path)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Record file not found") from None
    except ValueError:
        raise HTTPException(
            status_code=422, detail="Could not read stored lab report securely"
        ) from None

    ext = (file_type or Path(rel_path).suffix.lstrip(".") or "bin").lower()
    if ext not in ALLOWED_EXTS:
        ext = "bin"
    return await _ocr_bytes(plaintext, ext)


async def _run_analysis(raw_text: str, conf_payload: dict) -> dict:
    """AI extract + normalize. Never logs report text."""
    unit_conf = normalize_confidence(conf_payload.get("confidence"))
    low = bool(conf_payload.get("low_confidence", True))
    analysis = await analyze_lab_report(
        raw_text,
        ocr_confidence=unit_conf,
        ocr_low_confidence=low,
    )
    # Fail closed: unavailable / failed extraction must not look like success data.
    if not analysis.get("analysis_available", True):
        raise HTTPException(
            status_code=503,
            detail=(
                "Lab extraction is temporarily unavailable. "
                "Please retry or discuss your original report with your GP."
            ),
        )
    if analysis.get("extraction_status") == "incomplete" and not analysis.get("results"):
        # Incomplete but available — still return for review (empty) is OK;
        # mark review required (already set by normalizer).
        pass
    analysis["ocr"] = conf_payload
    analysis["user_confirmed"] = False
    analysis["review_required"] = True
    analysis["is_clinician_verified"] = False
    return analysis


def _response(record: MedicalRecord, analysis: dict, *, user_confirmed: bool) -> dict:
    return {
        "record_id": record.id,
        "user_confirmed": user_confirmed,
        "review_required": not user_confirmed,
        "is_clinician_verified": False,
        "guidance_type": "informational",
        "is_diagnosis": False,
        "analysis": analysis,
        "message": (
            "Extraction confirmed by you against the original report. "
            "This is not clinician verification."
            if user_confirmed
            else "Please review the extracted information against your original report."
        ),
    }


@router.post("/analyze")
async def analyze_uploaded_lab_report(
    file: UploadFile = File(...),
    family_member_id: Optional[int] = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Upload a lab report, extract values, and return a REVIEW-REQUIRED draft."""
    if family_member_id is not None:
        await _require_owned_active_family_member(
            db, family_member_id, current_user.id
        )

    filename = file.filename or "lab_report.bin"
    ext = _safe_ext(filename)
    content = await file.read()
    if len(content) > MAX_BYTES:
        raise HTTPException(
            status_code=400,
            detail=f"File too large. Maximum size: {MAX_BYTES // (1024 * 1024)} MB",
        )
    ctype = (file.content_type or "").split(";")[0].strip().lower()
    if ctype and ctype not in ALLOWED_MIME:
        raise HTTPException(status_code=400, detail=f"Unsupported MIME type: {ctype}")
    if ext != "heic":
        _validate_magic(ext, content)

    logger.info(
        "lab_analysis_upload user_id=%s file_bytes=%d ext=%s",
        current_user.id,
        len(content),
        ext,
    )

    raw_text, conf_payload = await _ocr_bytes(content, ext)
    if not raw_text.strip():
        raise HTTPException(
            status_code=422,
            detail=(
                "Could not extract text from file. "
                "Please upload a clearer image or PDF."
            ),
        )

    # Analyze before persistence so failed AI/OCR does not create trusted rows.
    analysis = await _run_analysis(raw_text, conf_payload)

    # Persist encrypted medical-record bytes (HN-RECORD-009).
    reupload = UploadFile(
        file=io.BytesIO(content),
        filename=filename,
        headers=Headers(
            {"content-type": ctype or "application/octet-stream"}
        ),
    )
    try:
        file_url = await save_encrypted_medical_file(
            reupload, folder=f"lab_reports/{current_user.id}"
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception:
        logger.exception(
            "lab_analysis_store_failed user_id=%s", current_user.id
        )
        raise HTTPException(
            status_code=500, detail="Could not store lab report securely"
        ) from None

    record = MedicalRecord(
        user_id=current_user.id,
        family_member_id=family_member_id,
        record_type="lab_report",
        title=filename,
        file_url=file_url,
        file_name=filename,
        file_type=ext,
        notes=_pack_notes(analysis, user_confirmed=False),
    )
    db.add(record)
    await db.commit()
    await db.refresh(record)

    logger.info(
        "lab_analysis_draft_saved user_id=%s record_id=%s result_count=%d "
        "review_required=true ocr_low=%s",
        current_user.id,
        record.id,
        len(analysis.get("results") or []),
        bool(conf_payload.get("low_confidence")),
    )
    return _response(record, analysis, user_confirmed=False)


@router.post("/analyze-record/{record_id}")
async def analyze_existing_record(
    record_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Re-extract an owned medical record as an unconfirmed lab draft."""
    result = await db.execute(
        select(MedicalRecord).where(
            MedicalRecord.id == record_id,
            MedicalRecord.user_id == current_user.id,
            MedicalRecord.is_active == True,  # noqa: E712
        )
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")

    raw_text, conf_payload = await _ocr_record_file(record.file_url, record.file_type)
    if not raw_text.strip():
        raise HTTPException(
            status_code=422,
            detail="Could not extract text from this record.",
        )

    analysis = await _run_analysis(raw_text, conf_payload)
    record.notes = _pack_notes(analysis, user_confirmed=False)
    await db.commit()
    await db.refresh(record)

    logger.info(
        "lab_analysis_reextract user_id=%s record_id=%s result_count=%d",
        current_user.id,
        record.id,
        len(analysis.get("results") or []),
    )
    return _response(record, analysis, user_confirmed=False)


@router.post("/confirm/{record_id}")
async def confirm_lab_analysis(
    record_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    User confirmation gate — marks stored extraction as user-reviewed.

    Does NOT imply clinician verification or diagnosis.
    """
    result = await db.execute(
        select(MedicalRecord).where(
            MedicalRecord.id == record_id,
            MedicalRecord.user_id == current_user.id,
            MedicalRecord.is_active == True,  # noqa: E712
        )
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")

    packed = _unpack_notes(record.notes)
    if not packed or not isinstance(packed.get("analysis"), dict):
        raise HTTPException(
            status_code=400,
            detail="No lab extraction draft available to confirm",
        )
    if packed.get("user_confirmed") is True:
        analysis = packed["analysis"]
        analysis["user_confirmed"] = True
        analysis["review_required"] = False
        return _response(record, analysis, user_confirmed=True)

    analysis = packed["analysis"]
    # Missing critical fields still allow confirm only if user insists —
    # but surface validation: require at least one result with a value.
    results = analysis.get("results") if isinstance(analysis, dict) else None
    if not isinstance(results, list) or not results:
        raise HTTPException(
            status_code=400,
            detail=(
                "Extraction has no result rows to confirm. "
                "Retry analysis or discuss your original report with your GP."
            ),
        )
    missing_critical = any(
        isinstance(r, dict) and (
            not r.get("parameter")
            or r.get("value") in (None, "")
            or "value" in (r.get("missing_fields") or [])
        )
        for r in results
    )
    if missing_critical:
        raise HTTPException(
            status_code=400,
            detail=(
                "One or more extracted results are missing a test name or value. "
                "Review the original report and retry analysis before confirming."
            ),
        )

    analysis = dict(analysis)
    analysis["user_confirmed"] = True
    analysis["review_required"] = False
    analysis["is_clinician_verified"] = False
    analysis["extraction_status"] = "user_confirmed"
    record.notes = _pack_notes(analysis, user_confirmed=True)
    await db.commit()
    await db.refresh(record)

    logger.info(
        "lab_analysis_confirmed user_id=%s record_id=%s result_count=%d",
        current_user.id,
        record.id,
        len(results),
    )
    return _response(record, analysis, user_confirmed=True)


@router.post("/reject/{record_id}")
async def reject_lab_analysis(
    record_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Discard an unconfirmed extraction draft (keeps the uploaded file)."""
    result = await db.execute(
        select(MedicalRecord).where(
            MedicalRecord.id == record_id,
            MedicalRecord.user_id == current_user.id,
            MedicalRecord.is_active == True,  # noqa: E712
        )
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")

    packed = _unpack_notes(record.notes)
    if packed and packed.get("user_confirmed") is True:
        raise HTTPException(
            status_code=400,
            detail="Confirmed extraction cannot be rejected via this endpoint",
        )

    record.notes = None
    await db.commit()
    logger.info(
        "lab_analysis_rejected user_id=%s record_id=%s",
        current_user.id,
        record.id,
    )
    return {
        "record_id": record.id,
        "user_confirmed": False,
        "review_required": True,
        "discarded": True,
        "message": "Unconfirmed extraction discarded. Original report file retained.",
    }
