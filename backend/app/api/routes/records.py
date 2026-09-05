from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from app.core.log_decorator import LoggedAPIRoute
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
from datetime import datetime

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.medical_record import MedicalRecord
from app.utils.storage import (
    save_encrypted_medical_file,
    read_medical_record_bytes,
    delete_file,
)
from app.core.logging_config import audit_log

router = APIRouter(route_class=LoggedAPIRoute)

VALID_TYPES = ["prescription", "lab_report", "radiology", "discharge_summary", "other"]

# Flutter historically sent "discharge"; canonical stored value is discharge_summary.
_RECORD_TYPE_ALIASES = {
    "discharge": "discharge_summary",
    "discharge_summary": "discharge_summary",
    "imaging": "radiology",  # legacy alias → radiology
}


def normalize_record_type(raw: str) -> str:
    key = (raw or "").strip().lower()
    return _RECORD_TYPE_ALIASES.get(key, key)


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
        canonical = normalize_record_type(record_type)
        if canonical == "discharge_summary":
            # Include legacy rows stored as "discharge" if any exist.
            query = query.where(
                MedicalRecord.record_type.in_(["discharge_summary", "discharge"])
            )
        else:
            query = query.where(MedicalRecord.record_type == canonical)
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
    canonical_type = normalize_record_type(record_type)
    if canonical_type not in VALID_TYPES:
        raise HTTPException(status_code=400, detail=f"Invalid record type. Use: {VALID_TYPES}")

    try:
        file_url = await save_encrypted_medical_file(
            file, folder=f"records/{current_user.id}"
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception:
        raise HTTPException(
            status_code=500, detail="Could not store medical record securely"
        ) from None

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
        record_type=canonical_type,
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
        extra={
            "user_id": current_user.id,
            "record_type": canonical_type,
            "record_id": record.id,
        },
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
    Authenticated file download — owner-scoped.

    Decrypts encrypted-at-rest medical files after authorization.
    Never returns ciphertext to the client.
    """
    record = await _get_record(db, record_id, current_user.id)

    try:
        plaintext = read_medical_record_bytes(record.file_url)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="File not found on server")
    except ValueError:
        # Corrupt ciphertext / wrong key — fail closed, no garbage body.
        raise HTTPException(
            status_code=500, detail="Could not read medical record file"
        ) from None

    audit_log.info(
        "medical_record_downloaded",
        extra={
            "user_id": current_user.id,
            "record_id": record_id,
            "byte_length": len(plaintext),
        },
    )

    safe_name = (record.file_name or "record.bin").replace('"', "")
    return Response(
        content=plaintext,
        media_type="application/octet-stream",
        headers={
            "Content-Disposition": f'attachment; filename="{safe_name}"',
        },
    )


@router.delete("/{record_id}")
async def delete_record(
    record_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    record = await _get_record(db, record_id, current_user.id)
    # Soft-delete metadata and remove on-disk PHI when local storage is used.
    stored_path = record.file_url
    record.is_active = False
    await db.commit()
    delete_file(stored_path)
    audit_log.info(
        "medical_record_deleted",
        extra={"user_id": current_user.id, "record_id": record_id},
    )
    return {"message": "Record deleted"}


async def _get_record(db: AsyncSession, record_id: int, user_id: int) -> MedicalRecord:
    result = await db.execute(
        select(MedicalRecord).where(
            MedicalRecord.id == record_id,
            MedicalRecord.user_id == user_id,
            MedicalRecord.is_active == True,
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
