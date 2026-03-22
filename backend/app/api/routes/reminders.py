from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import json
from typing import Optional

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.medication_schedule import MedicationSchedule
from app.schemas.medication import MedicationScheduleCreate, MedicationScheduleUpdate, MedicationScheduleResponse

router = APIRouter()


@router.get("/", response_model=list[MedicationScheduleResponse])
async def list_reminders(
    active_only: bool = True,
    family_member_id: Optional[int] = None,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = select(MedicationSchedule).where(
        MedicationSchedule.user_id == current_user.id
    ).order_by(MedicationSchedule.created_at.desc())

    if active_only:
        query = query.where(MedicationSchedule.is_active == True)
    if family_member_id:
        query = query.where(MedicationSchedule.family_member_id == family_member_id)

    result = await db.execute(query)
    schedules = result.scalars().all()
    return [_to_response(s) for s in schedules]


@router.post("/", response_model=MedicationScheduleResponse)
async def create_reminder(
    data: MedicationScheduleCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    schedule = MedicationSchedule(
        user_id=current_user.id,
        family_member_id=data.family_member_id,
        medicine_name=data.medicine_name,
        dosage=data.dosage,
        frequency=data.frequency,
        times=json.dumps(data.times or []),
        instructions=data.instructions,
        start_date=data.start_date,
        end_date=data.end_date,
        refill_date=data.refill_date,
        total_quantity=data.total_quantity,
        remaining_quantity=data.remaining_quantity,
        prescription_id=data.prescription_id,
    )
    db.add(schedule)
    await db.commit()
    await db.refresh(schedule)
    return _to_response(schedule)


@router.get("/{schedule_id}", response_model=MedicationScheduleResponse)
async def get_reminder(
    schedule_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    schedule = await _get_schedule(db, schedule_id, current_user.id)
    return _to_response(schedule)


@router.put("/{schedule_id}", response_model=MedicationScheduleResponse)
async def update_reminder(
    schedule_id: int,
    data: MedicationScheduleUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    schedule = await _get_schedule(db, schedule_id, current_user.id)

    if data.medicine_name is not None:
        schedule.medicine_name = data.medicine_name
    if data.dosage is not None:
        schedule.dosage = data.dosage
    if data.frequency is not None:
        schedule.frequency = data.frequency
    if data.times is not None:
        schedule.times = json.dumps(data.times)
    if data.instructions is not None:
        schedule.instructions = data.instructions
    if data.end_date is not None:
        schedule.end_date = data.end_date
    if data.refill_date is not None:
        schedule.refill_date = data.refill_date
    if data.remaining_quantity is not None:
        schedule.remaining_quantity = data.remaining_quantity
    if data.is_active is not None:
        schedule.is_active = data.is_active

    await db.commit()
    await db.refresh(schedule)
    return _to_response(schedule)


@router.delete("/{schedule_id}")
async def delete_reminder(
    schedule_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    schedule = await _get_schedule(db, schedule_id, current_user.id)
    schedule.is_active = False
    await db.commit()
    return {"message": "Reminder deleted"}


async def _get_schedule(db: AsyncSession, schedule_id: int, user_id: int) -> MedicationSchedule:
    result = await db.execute(
        select(MedicationSchedule).where(
            MedicationSchedule.id == schedule_id,
            MedicationSchedule.user_id == user_id,
        )
    )
    schedule = result.scalar_one_or_none()
    if not schedule:
        raise HTTPException(status_code=404, detail="Reminder not found")
    return schedule


def _to_response(s: MedicationSchedule) -> dict:
    return {
        "id": s.id,
        "user_id": s.user_id,
        "family_member_id": s.family_member_id,
        "medicine_name": s.medicine_name,
        "dosage": s.dosage,
        "frequency": s.frequency,
        "times": json.loads(s.times) if s.times else [],
        "instructions": s.instructions,
        "start_date": s.start_date,
        "end_date": s.end_date,
        "refill_date": s.refill_date,
        "total_quantity": s.total_quantity,
        "remaining_quantity": s.remaining_quantity,
        "is_active": s.is_active,
        "created_at": s.created_at,
    }
