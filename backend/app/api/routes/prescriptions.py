from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
import json

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.prescription import Prescription
from app.models.medical_record import MedicalRecord
from app.utils.storage import save_file
from app.services.ocr_service import extract_prescription_text
from app.services.ai_service import analyze_prescription

router = APIRouter()


@router.post("/scan")
async def scan_prescription(
    file: UploadFile = File(...),
    family_member_id: Optional[int] = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Save file
    file_url = await save_file(file, folder=f"prescriptions/{current_user.id}")
    file_type = file.filename.rsplit(".", 1)[-1].lower() if file.filename else "unknown"

    # Save as medical record
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

    # OCR extraction
    raw_text = await extract_prescription_text(file_url)

    # AI analysis
    ai_result = await analyze_prescription(raw_text)

    prescription = Prescription(
        user_id=current_user.id,
        medical_record_id=record.id,
        family_member_id=family_member_id,
        raw_ocr_text=raw_text,
        extracted_medicines=json.dumps(ai_result.get("medicines", [])),
        doctor_name=ai_result.get("doctor_name"),
        hospital=ai_result.get("hospital"),
        ai_summary=ai_result.get("summary"),
    )
    db.add(prescription)
    await db.commit()
    await db.refresh(prescription)

    return {
        "id": prescription.id,
        "raw_text": raw_text,
        "medicines": ai_result.get("medicines", []),
        "doctor_name": ai_result.get("doctor_name"),
        "hospital": ai_result.get("hospital"),
        "summary": ai_result.get("summary"),
        "medical_record_id": record.id,
    }


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
