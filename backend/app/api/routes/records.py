from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from app.core.log_decorator import LoggedAPIRoute
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
from datetime import datetime
import os

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.medical_record import MedicalRecord
from app.utils.storage import save_file
from app.core.config import settings
from app.core.logging_config import audit_log

router = APIRouter(route_class=LoggedAPIRoute)

VALID_TYPES = ["prescription", "lab_report", "radiology", "discharge_summary", "other"]


@router.get("/")
async def list_records(
    record_type: Optional[str] = None,
    family_member_id: Optional[int] = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = select(MedicalRecord).where(
        MedicalRecord.user_id == current_user.id,
        MedicalRecord.is_active == True,
    ).order_by(MedicalRecord.created_at.desc()).limit(100)

    if record_type:
        query = query.where(MedicalRecord.record_type == record_type)
    if family_member_id:
        query = query.where(MedicalRecord.family_member_id == family_member_id)

    result = await db.execute(query)
    records = result.scalars().all()
    return [_to_dict(r) for r in records]


@router.post("/upload")
async def upload_record(
    file: UploadFile = File(...),
    record_type: str = Form(...),
    title: Optional[str] = Form(None),
    notes: Optional[str] = Form(None),
    family_member_id: Optional[int] = Form(None),
    record_date: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if record_type not in VALID_TYPES:
        raise HTTPException(status_code=400, detail=f"Invalid record type. Use: {VALID_TYPES}")

    file_url = await save_file(file, folder=f"records/{current_user.id}")
    file_type = file.filename.rsplit(".", 1)[-1].lower() if file.filename else "unknown"

    parsed_date = None
    if record_date:
        try:
            parsed_date = datetime.fromisoformat(record_date)
        except ValueError:
            pass

    record = MedicalRecord(
        user_id=current_user.id,
        family_member_id=family_member_id,
        record_type=record_type,
        title=title or file.filename,
        file_url=file_url,
        file_name=file.filename,
        file_type=file_type,
        notes=notes,
        record_date=parsed_date,
    )
    db.add(record)
    await db.commit()
    await db.refresh(record)

    audit_log.info(
        "medical_record_uploaded",
        extra={"user_id": current_user.id, "record_type": record_type, "record_id": record.id},
    )
    return _to_dict(record)


@router.get("/{record_id}")
async def get_record(
    record_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    record = await _get_record(db, record_id, current_user.id)
    return _to_dict(record)


@router.get("/{record_id}/file")
async def download_record_file(
    record_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Authenticated file download — verifies the requesting user owns this record
    before serving the file. Replaces direct /uploads static access.
    """
    record = await _get_record(db, record_id, current_user.id)

    file_path = os.path.join(settings.LOCAL_UPLOAD_DIR, record.file_url)
    if not os.path.isfile(file_path):
        raise HTTPException(status_code=404, detail="File not found on server")

    audit_log.info(
        "medical_record_downloaded",
        extra={"user_id": current_user.id, "record_id": record_id},
    )

    return FileResponse(
        path=file_path,
        filename=record.file_name,
        media_type="application/octet-stream",
    )


@router.delete("/{record_id}")
async def delete_record(
    record_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    record = await _get_record(db, record_id, current_user.id)
    record.is_active = False
    await db.commit()
    return {"message": "Record deleted"}


async def _get_record(db: AsyncSession, record_id: int, user_id: int) -> MedicalRecord:
    result = await db.execute(
        select(MedicalRecord).where(
            MedicalRecord.id == record_id,
            MedicalRecord.user_id == user_id,
        )
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")
    return record


def _to_dict(r: MedicalRecord) -> dict:
    return {
        "id": r.id,
        "user_id": r.user_id,
        "family_member_id": r.family_member_id,
        "record_type": r.record_type,
        "title": r.title,
        # Use authenticated download URL instead of direct static path
        "file_url": f"/api/v1/records/{r.id}/file",
        "file_name": r.file_name,
        "file_type": r.file_type,
        "notes": r.notes,  # decrypted by EncryptedText TypeDecorator
        "record_date": r.record_date,
        "created_at": r.created_at,
    }
