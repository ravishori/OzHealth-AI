from fastapi import APIRouter, Depends, HTTPException
from app.core.log_decorator import LoggedAPIRoute
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import json
from typing import Optional

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.family_member import FamilyMember
from app.models.medication_schedule import MedicationSchedule
from app.schemas.medication import (
    MedicationScheduleCreate,
    MedicationScheduleUpdate,
    MedicationScheduleResponse,
)

router = APIRouter(route_class=LoggedAPIRoute)


async def _require_owned_active_family_member(
    db: AsyncSession,
    family_member_id: int,
    user_id: int,
) -> FamilyMember:
    """
    Authoritative ownership check for family_member_id.

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


async def _family_names_for_schedules(
    db: AsyncSession,
    schedules: list[MedicationSchedule],
    user_id: int,
) -> dict[int, str]:
    ids = {s.family_member_id for s in schedules if s.family_member_id}
    if not ids:
        return {}
    result = await db.execute(
        select(FamilyMember).where(
            FamilyMember.id.in_(ids),
            FamilyMember.user_id == user_id,
        )
    )
    members = result.scalars().all()
    return {m.id: m.name for m in members}


def _to_response(
    s: MedicationSchedule,
    *,
    family_member_name: Optional[str] = None,
) -> dict:
    return {
        "id": s.id,
        "user_id": s.user_id,
        "family_member_id": s.family_member_id,
        "family_member_name": family_member_name,
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


async def _respond(
    db: AsyncSession,
    schedule: MedicationSchedule,
    user_id: int,
) -> dict:
    name = None
    if schedule.family_member_id:
        names = await _family_names_for_schedules(db, [schedule], user_id)
        name = names.get(schedule.family_member_id)
    return _to_response(schedule, family_member_name=name)


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
        query = query.where(MedicationSchedule.is_active == True)  # noqa: E712
    if family_member_id:
        # Filter only after proving the member is owned (avoids probing foreign ids)
        await _require_owned_active_family_member(
            db, family_member_id, current_user.id
        )
        query = query.where(MedicationSchedule.family_member_id == family_member_id)

    result = await db.execute(query)
    schedules = result.scalars().all()
    names = await _family_names_for_schedules(db, schedules, current_user.id)
    return [
        _to_response(
            s,
            family_member_name=names.get(s.family_member_id)
            if s.family_member_id
            else None,
        )
        for s in schedules
    ]


@router.post("/", response_model=MedicationScheduleResponse)
async def create_reminder(
    data: MedicationScheduleCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member_name = None
    if data.family_member_id is not None:
        member = await _require_owned_active_family_member(
            db, data.family_member_id, current_user.id
        )
        member_name = member.name

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
        is_active=True,
    )
    db.add(schedule)
    await db.commit()
    await db.refresh(schedule)
    return _to_response(schedule, family_member_name=member_name)


@router.get("/{schedule_id}", response_model=MedicationScheduleResponse)
async def get_reminder(
    schedule_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    schedule = await _get_schedule(db, schedule_id, current_user.id)
    return await _respond(db, schedule, current_user.id)


@router.put("/{schedule_id}", response_model=MedicationScheduleResponse)
async def update_reminder(
    schedule_id: int,
    data: MedicationScheduleUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    schedule = await _get_schedule(db, schedule_id, current_user.id)

    # family_member_id: None means "unchanged"; use sentinel via model_fields_set
    if "family_member_id" in data.model_fields_set:
        if data.family_member_id is None:
            schedule.family_member_id = None
        else:
            await _require_owned_active_family_member(
                db, data.family_member_id, current_user.id
            )
            schedule.family_member_id = data.family_member_id

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
    # refill_date: omit = unchanged; explicit null = clear (HN-REM-009)
    if "refill_date" in data.model_fields_set:
        schedule.refill_date = data.refill_date
    if data.total_quantity is not None:
        schedule.total_quantity = data.total_quantity
    if data.remaining_quantity is not None:
        schedule.remaining_quantity = data.remaining_quantity
    if data.is_active is not None:
        schedule.is_active = data.is_active

    await db.commit()
    await db.refresh(schedule)
    return await _respond(db, schedule, current_user.id)


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


async def _get_schedule(
    db: AsyncSession, schedule_id: int, user_id: int
) -> MedicationSchedule:
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
