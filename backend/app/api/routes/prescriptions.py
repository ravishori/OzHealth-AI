from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, Query
from app.core.log_decorator import LoggedAPIRoute
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
import json
import os

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.prescription import Prescription
from app.models.medical_record import MedicalRecord
from app.utils.storage import save_file
from app.services.ai_service import check_allergy_conflicts, detect_duplicate_medicines
from app.services.prescription_ocr_pipeline import (
    PrescriptionOcrPipeline,
    PrescriptionUploadError,
    save_temp_upload,
)

router = APIRouter(route_class=LoggedAPIRoute)


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

    duplicate_check = None
    if len(medicine_names) >= 2:
        duplicate_check = await detect_duplicate_medicines(medicine_names)

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
    }


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
    return _to_dict(p)


def _to_dict(p: Prescription) -> dict:
    return {
        "id": p.id,
        "user_id": p.user_id,
        "family_member_id": p.family_member_id,
        "medical_record_id": p.medical_record_id,
        "doctor_name": p.doctor_name,
        "hospital": p.hospital,
        "prescription_date": p.prescription_date,
        "medicines": json.loads(p.extracted_medicines) if p.extracted_medicines else [],
        "ai_summary": p.ai_summary,
        "created_at": p.created_at,
    }
