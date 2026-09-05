"""
Lab Report Analyzer — Feature #29
POST /api/v1/lab-analysis/analyze  (upload file)
POST /api/v1/lab-analysis/analyze-record/{record_id}  (existing record)
"""
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional

from app.core.log_decorator import LoggedAPIRoute
from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.medical_record import MedicalRecord
from app.utils.storage import save_file
from app.services.ocr_service import extract_prescription_text
from app.services.ai_service import analyze_lab_report

router = APIRouter(route_class=LoggedAPIRoute)


@router.post("/analyze")
async def analyze_uploaded_lab_report(
    file: UploadFile = File(...),
    family_member_id: Optional[int] = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Upload and analyse a lab report (image or PDF)."""
    file_url = await save_file(file, folder=f"lab_reports/{current_user.id}")
    file_type = file.filename.rsplit(".", 1)[-1].lower() if file.filename else "unknown"

    # Save as medical record
    record = MedicalRecord(
        user_id=current_user.id,
        family_member_id=family_member_id,
        record_type="lab_report",
        title=file.filename or "Lab Report",
        file_url=file_url,
        file_name=file.filename,
        file_type=file_type,
    )
    db.add(record)
    await db.flush()

    # Extract text via OCR
    raw_text = await extract_prescription_text(file_url)
    if not raw_text.strip():
        raise HTTPException(status_code=422, detail="Could not extract text from file. Please upload a clearer image or PDF.")

    # AI analysis
    analysis = await analyze_lab_report(raw_text)

    # Save analysis back to record notes
    import json
    record.notes = json.dumps(analysis)
    await db.commit()
    await db.refresh(record)

    return {
        "record_id": record.id,
        "analysis": analysis,
    }


@router.post("/analyze-record/{record_id}")
async def analyze_existing_record(
    record_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Analyse an already-uploaded medical record as a lab report."""
    result = await db.execute(
        select(MedicalRecord).where(
            MedicalRecord.id == record_id,
            MedicalRecord.user_id == current_user.id,
        )
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")

    raw_text = await extract_prescription_text(record.file_url)
    if not raw_text.strip():
        raise HTTPException(status_code=422, detail="Could not extract text from this record.")

    analysis = await analyze_lab_report(raw_text)

    import json
    record.notes = json.dumps(analysis)
    await db.commit()

    return {
        "record_id": record.id,
        "analysis": analysis,
    }
