from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Query
from app.core.log_decorator import LoggedAPIRoute
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional, Any
import json
import os

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.prescription import Prescription
from app.models.medical_record import MedicalRecord
from app.models.family_member import FamilyMember
from app.schemas.prescription import ManualPrescriptionCreate
from app.utils.storage import save_file
from app.services.ai_service import check_allergy_conflicts
from app.services.medicine_safety_service import MedicineSafetyChecker
from app.services.prescription_ocr_pipeline import (
    PrescriptionOcrPipeline,
    PrescriptionUploadError,
    save_temp_upload,
)

_MANUAL_SUMMARY = (
    "Manual prescription entry — user-supplied information only. "
    "Not OCR-derived. Not clinically verified."
)

router = APIRouter(route_class=LoggedAPIRoute)

_DUP_NOTE = (
    "Possible duplicate medicines only — not a clinical diagnosis. "
    "Confirm with a doctor or pharmacist before changing or stopping medicines."
)


async def _require_owned_active_family_member(
    db: AsyncSession,
    family_member_id: int,
    user_id: int,
) -> FamilyMember:
    """
    Authoritative ownership check for family_member_id (same semantics as reminders).

    Returns 404 for missing, inactive, or cross-user members — does not
    disclose whether the id exists for another user.
    """
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


def _sanitize_manual_medicines(medicines: list) -> list[dict]:
    """Persist only safe user-confirmed fields; never invent catalogue identity."""
    sanitized: list[dict] = []
    for m in medicines:
        if hasattr(m, "model_dump"):
            raw = m.model_dump()
        elif isinstance(m, dict):
            raw = m
        else:
            continue
        name = (raw.get("name") or "").strip()
        if not name:
            continue
        catalog_id = raw.get("catalog_medicine_id")
        if catalog_id is None:
            catalog_id = raw.get("medicine_id")
        try:
            catalog_id = int(catalog_id) if catalog_id is not None else None
        except (TypeError, ValueError):
            catalog_id = None
        if catalog_id is not None and catalog_id < 1:
            catalog_id = None
        match_status = (raw.get("match_status") or "").strip().upper() or (
            "MATCHED" if catalog_id else "UNMATCHED"
        )
        if catalog_id is None:
            match_status = "UNMATCHED"
        entry: dict[str, Any] = {
            "name": name,
            "dosage": raw.get("dosage") or None,
            "frequency": raw.get("frequency") or None,
            "duration": raw.get("duration") or None,
            "instructions": raw.get("instructions") or None,
            "quantity": raw.get("quantity") or None,
            "catalog_medicine_id": catalog_id,
            "artg_number": raw.get("artg_number") or None,
            "match_status": match_status,
            "user_confirmed": True,
            "source": "manual",
            "entry_mode": "manual",
        }
        sanitized.append(entry)
    return sanitized


def _infer_entry_mode(medicines: list, raw_ocr_text: Optional[str]) -> Optional[str]:
    """Distinguish manual vs OCR provenance without a schema migration."""
    if isinstance(medicines, list):
        for m in medicines:
            if not isinstance(m, dict):
                continue
            mode = (m.get("entry_mode") or "").strip().lower()
            if mode == "manual":
                return "manual"
            source = (m.get("source") or "").strip().lower()
            if source == "manual":
                return "manual"
    if raw_ocr_text:
        return "ocr"
    if isinstance(medicines, list):
        for m in medicines:
            if not isinstance(m, dict):
                continue
            if (m.get("source") or "").strip().lower() == "user_confirmed":
                return "ocr"
            if (m.get("entry_mode") or "").strip().lower() == "ocr":
                return "ocr"
    return None


async def _allergy_alerts_for_user(current_user: User, medicine_names: list[str]):
    allergy_check = None
    if medicine_names and current_user.allergies:
        try:
            allergies = (
                json.loads(current_user.allergies)
                if isinstance(current_user.allergies, str)
                else current_user.allergies
            )
            if isinstance(allergies, list) and allergies:
                allergy_check = await check_allergy_conflicts(medicine_names, allergies)
        except Exception:
            pass
    return allergy_check


def _catalog_medicine_ids(medicines: list) -> list[int]:
    """Extract confirmed catalogue medicine_ids from stored/confirmed medicine rows."""
    ids: list[int] = []
    seen: set[int] = set()
    for m in medicines:
        if not isinstance(m, dict):
            continue
        raw = m.get("catalog_medicine_id") if m.get("catalog_medicine_id") is not None else m.get("medicine_id")
        if raw is None or raw == "":
            continue
        try:
            mid = int(raw)
        except (TypeError, ValueError):
            continue
        if mid < 1 or mid in seen:
            continue
        seen.add(mid)
        ids.append(mid)
    return ids


async def catalogue_duplicate_warnings(
    db: AsyncSession,
    medicines: list,
) -> dict:
    """
    HN-MED-007 — catalogue-grounded possible-duplicate warnings.

    Uses MedicineSafetyChecker catalogue identity only
    (same medicine_id or same non-empty normalized canonical_key).
    Does NOT call an LLM as the authoritative detector.
    Does NOT treat same generic_name or shared ingredients as duplicates.
    """
    ids = _catalog_medicine_ids(medicines if isinstance(medicines, list) else [])
    if len(ids) < 2:
        return {
            "safe": True,
            "duplicates": [],
            "summary": (
                "Duplicate check needs at least two catalogue-matched medicines."
            ),
            "source": "database",
            "available": False,
            "note": _DUP_NOTE,
        }
    try:
        result = await MedicineSafetyChecker(db).check(ids)
    except (LookupError, ValueError):
        return {
            "safe": True,
            "duplicates": [],
            "summary": "Catalogue duplicate check unavailable for these medicines.",
            "source": "database",
            "available": False,
            "note": _DUP_NOTE,
        }

    pairs = []
    for d in result.get("duplicates") or []:
        a = d.get("medicine_a") or {}
        b = d.get("medicine_b") or {}
        a_name = a.get("name") if isinstance(a, dict) else str(a)
        b_name = b.get("name") if isinstance(b, dict) else str(b)
        a_id = a.get("medicine_id") if isinstance(a, dict) else None
        b_id = b.get("medicine_id") if isinstance(b, dict) else None
        reason = (d.get("reason") or "").strip() or (
            "These medicines appear to have the same catalogue identity."
        )
        pairs.append(
            {
                "medicine_a": a_name,
                "medicine_b": b_name,
                "medicine_a_id": a_id,
                "medicine_b_id": b_id,
                "reason": reason,
                # Compatibility with existing Flutter detail widget field name.
                "risk": reason,
                "recommendation": (
                    "Ask a doctor or pharmacist to confirm whether these "
                    "are intended duplicates. Do not stop or change medicines "
                    "based on this warning alone."
                ),
                "source": "database",
                "status": "DUPLICATE",
            }
        )
    return {
        "safe": len(pairs) == 0,
        "duplicates": pairs,
        "summary": (
            f"{len(pairs)} possible duplicate pair(s) from catalogue identity."
            if pairs
            else "No catalogue duplicate pairs detected."
        ),
        "source": "database",
        "available": True,
        "note": _DUP_NOTE,
    }


@router.post("/ocr")
async def prescription_ocr_minimum(
    file: UploadFile = File(..., description="Prescription JPG/JPEG/PNG/PDF"),
    limit: int = Query(5, ge=1, le=20, description="Max catalog candidates per extracted medicine"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Minimum prescription OCR pipeline (no clinical intelligence):

      upload → OCR → extract medicine text → catalog search → candidates

    Distinguishes OCR-extracted fields from database-confirmed candidates.
    Temporary file only — not persisted. No diagnosis / interactions / advice.
    """
    tmp_path = None
    try:
        tmp_path, _ext, _size = await save_temp_upload(file)
        pipeline = PrescriptionOcrPipeline(db)
        result = await pipeline.process_file(
            tmp_path,
            original_filename=file.filename,
            search_limit=limit,
        )
        result["user_id"] = current_user.id
        result["requires_confirmation"] = True
        result["permanent_storage"] = False
        return result
    except PrescriptionUploadError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"OCR pipeline failed: {exc}") from exc
    finally:
        if tmp_path is not None:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


@router.post("/confirm")
async def confirm_prescription(
    file: UploadFile = File(...),
    medicines_json: str = Form(..., description="User-confirmed medicines JSON array"),
    doctor_name: Optional[str] = Form(None),
    hospital: Optional[str] = Form(None),
    ai_summary: Optional[str] = Form(None),
    raw_ocr_text: Optional[str] = Form(None),
    family_member_id: Optional[int] = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Persist a prescription only after explicit user confirmation.

    Medicines must be the user-reviewed list (may include catalog ids / edited names).
    Does not invent medicine identities when unmatched.
    """
    try:
        medicines = json.loads(medicines_json)
        if not isinstance(medicines, list):
            raise ValueError("medicines_json must be a JSON array")
    except (json.JSONDecodeError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=f"Invalid medicines_json: {exc}") from exc

    # Strip any accidental "confirmed clinical" claims from client payloads.
    sanitized = []
    for m in medicines:
        if not isinstance(m, dict):
            continue
        entry = {
            "name": (m.get("name") or m.get("extracted_name") or "").strip(),
            "dosage": m.get("dosage") or m.get("extracted_strength"),
            "frequency": m.get("frequency") or m.get("extracted_frequency"),
            "duration": m.get("duration"),
            "quantity": m.get("quantity"),
            "catalog_medicine_id": m.get("catalog_medicine_id") or m.get("medicine_id"),
            "artg_number": m.get("artg_number") or m.get("ARTG"),
            "match_status": m.get("match_status") or (
                "MATCHED" if m.get("catalog_medicine_id") or m.get("medicine_id") else "UNMATCHED"
            ),
            "user_confirmed": True,
            "source": "user_confirmed",
            "entry_mode": "ocr",
        }
        if entry["name"]:
            sanitized.append(entry)

    if not sanitized:
        raise HTTPException(
            status_code=400,
            detail="At least one medicine with a name is required to save.",
        )

    file_url = await save_file(file, folder=f"prescriptions/{current_user.id}")
    file_type = file.filename.rsplit(".", 1)[-1].lower() if file.filename else "unknown"

    record = MedicalRecord(
        user_id=current_user.id,
        family_member_id=family_member_id,
        record_type="prescription",
        title=file.filename,
        file_url=file_url,
        file_name=file.filename,
        file_type=file_type,
    )
    db.add(record)
    await db.flush()

    prescription = Prescription(
        user_id=current_user.id,
        medical_record_id=record.id,
        family_member_id=family_member_id,
        raw_ocr_text=raw_ocr_text,
        extracted_medicines=json.dumps(sanitized),
        doctor_name=doctor_name,
        hospital=hospital,
        ai_summary=ai_summary or "Saved after user confirmation of OCR extraction.",
    )
    db.add(prescription)
    await db.commit()
    await db.refresh(prescription)

    medicine_names = [m["name"] for m in sanitized]
    allergy_check = await _allergy_alerts_for_user(current_user, medicine_names)

    # HN-MED-007 — catalogue-grounded duplicates (not AI-as-authority).
    duplicate_check = await catalogue_duplicate_warnings(db, sanitized)

    return {
        "id": prescription.id,
        "medicines": sanitized,
        "doctor_name": doctor_name,
        "hospital": hospital,
        "summary": prescription.ai_summary,
        "medical_record_id": record.id,
        "allergy_alerts": allergy_check,
        "duplicate_warnings": duplicate_check,
        "user_confirmed": True,
        "entry_mode": "ocr",
    }


@router.post("/manual")
async def create_manual_prescription(
    body: ManualPrescriptionCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    HN-RX-003 — persist a manually entered prescription (no OCR file, no LLM).

    Additional entry mode alongside POST /ocr + POST /confirm.
    Does not upload a fake OCR file or fabricate OCR output.
    """
    sanitized = _sanitize_manual_medicines(body.medicines)
    if not sanitized:
        raise HTTPException(
            status_code=400,
            detail="At least one medicine with a name is required to save.",
        )

    family_member_id = body.family_member_id
    if family_member_id is not None:
        await _require_owned_active_family_member(
            db, family_member_id, current_user.id
        )

    # No MedicalRecord / file — medical_record_id remains null (schema allows it).
    prescription = Prescription(
        user_id=current_user.id,
        medical_record_id=None,
        family_member_id=family_member_id,
        raw_ocr_text=None,
        extracted_medicines=json.dumps(sanitized),
        doctor_name=body.doctor_name,
        hospital=body.hospital,
        ai_summary=_MANUAL_SUMMARY,
    )
    db.add(prescription)
    await db.commit()
    await db.refresh(prescription)

    medicine_names = [m["name"] for m in sanitized]
    allergy_check = await _allergy_alerts_for_user(current_user, medicine_names)
    duplicate_check = await catalogue_duplicate_warnings(db, sanitized)

    data = _to_dict(prescription)
    data["allergy_alerts"] = allergy_check
    data["duplicate_warnings"] = duplicate_check
    data["user_confirmed"] = True
    data["summary"] = prescription.ai_summary
    return data


@router.post("/scan")
async def scan_prescription(
    file: UploadFile = File(...),
    family_member_id: Optional[int] = Form(None),
    persist: bool = Form(
        False,
        description="Legacy auto-save. Default False — use /ocr + /confirm instead.",
    ),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Legacy scan endpoint.

    Sprint 1 default: does NOT persist. Prefer POST /ocr then POST /confirm.
    Set persist=true only for explicit legacy callers that still need auto-save.
    """
    if not persist:
        # Non-persisting preview: OCR + catalog match (same safety as /ocr).
        tmp_path = None
        try:
            tmp_path, _ext, _size = await save_temp_upload(file)
            pipeline = PrescriptionOcrPipeline(db)
            result = await pipeline.process_file(
                tmp_path,
                original_filename=file.filename,
                search_limit=5,
            )
            result["user_id"] = current_user.id
            result["requires_confirmation"] = True
            result["permanent_storage"] = False
            result["legacy_scan"] = True
            result["message"] = (
                "Preview only — prescription was NOT saved. "
                "Confirm via POST /prescriptions/confirm after review."
            )
            return result
        except PrescriptionUploadError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except Exception as exc:
            raise HTTPException(status_code=500, detail=f"OCR pipeline failed: {exc}") from exc
        finally:
            if tmp_path is not None:
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass

    # Explicit legacy persist path — disabled (HN-OCR-003).
    # Silent AI auto-save bypassed confirm-before-save and confidence review.
    raise HTTPException(
        status_code=400,
        detail=(
            "Legacy persist=true auto-save is disabled. "
            "Use POST /prescriptions/ocr, review the result, then "
            "POST /prescriptions/confirm."
        ),
    )


@router.get("/")
async def list_prescriptions(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Prescription)
        .where(Prescription.user_id == current_user.id)
        .order_by(Prescription.created_at.desc())
    )
    prescriptions = result.scalars().all()
    return [_to_dict(p) for p in prescriptions]


@router.get("/{prescription_id}")
async def get_prescription(
    prescription_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(Prescription).where(
            Prescription.id == prescription_id,
            Prescription.user_id == current_user.id,
        )
    )
    p = result.scalar_one_or_none()
    if not p:
        raise HTTPException(status_code=404, detail="Prescription not found")
    data = _to_dict(p)
    # HN-MED-007 — recompute on read so detail UI can surface warnings.
    meds = data.get("medicines") if isinstance(data.get("medicines"), list) else []
    data["duplicate_warnings"] = await catalogue_duplicate_warnings(db, meds)
    return data


def _to_dict(p: Prescription) -> dict:
    medicines = json.loads(p.extracted_medicines) if p.extracted_medicines else []
    raw_ocr = getattr(p, "raw_ocr_text", None)
    return {
        "id": p.id,
        "user_id": p.user_id,
        "family_member_id": p.family_member_id,
        "medical_record_id": p.medical_record_id,
        "doctor_name": p.doctor_name,
        "hospital": p.hospital,
        "prescription_date": p.prescription_date,
        "medicines": medicines,
        "ai_summary": p.ai_summary,
        "entry_mode": _infer_entry_mode(medicines, raw_ocr),
        "created_at": p.created_at,
    }
