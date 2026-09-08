"""HN-REM-010 — Appointment CRUD (local reminders scheduled on device).

Server stores appointment metadata only. Local notification scheduling is
performed by the Flutter client via LocalReminderNotifications — no FCM.
"""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.log_decorator import LoggedAPIRoute
from app.models.user import User
from app.models.family_member import FamilyMember
from app.models.appointment import Appointment
from app.schemas.appointment import (
    AppointmentCreate,
    AppointmentUpdate,
    AppointmentResponse,
)

router = APIRouter(route_class=LoggedAPIRoute)


async def _require_owned_active_family_member(
    db: AsyncSession,
    family_member_id: int,
    user_id: int,
) -> FamilyMember:
    """Same safe 404 semantics as reminders / health_metrics."""
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


async def _get_appointment(
    db: AsyncSession, appointment_id: int, user_id: int
) -> Appointment:
    result = await db.execute(
        select(Appointment).where(
            Appointment.id == appointment_id,
            Appointment.user_id == user_id,
        )
    )
    appt = result.scalar_one_or_none()
    if not appt:
        raise HTTPException(status_code=404, detail="Appointment not found")
    return appt


async def _family_names(
    db: AsyncSession,
    appointments: list[Appointment],
    user_id: int,
) -> dict[int, str]:
    ids = {a.family_member_id for a in appointments if a.family_member_id}
    if not ids:
        return {}
    result = await db.execute(
        select(FamilyMember).where(
            FamilyMember.id.in_(ids),
            FamilyMember.user_id == user_id,
        )
    )
    return {m.id: m.name for m in result.scalars().all()}


def _to_response(
    a: Appointment, *, family_member_name: Optional[str] = None
) -> dict:
    return {
        "id": a.id,
        "user_id": a.user_id,
        "family_member_id": a.family_member_id,
        "family_member_name": family_member_name,
        "title": a.title,
        "scheduled_at": a.scheduled_at,
        "notes": a.notes,
        "remind_before_minutes": a.remind_before_minutes,
        "is_active": a.is_active,
        "created_at": a.created_at,
    }


@router.get("/", response_model=list[AppointmentResponse])
async def list_appointments(
    active_only: bool = True,
    family_member_id: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = select(Appointment).where(
        Appointment.user_id == current_user.id
    ).order_by(Appointment.scheduled_at.asc())

    if active_only:
        query = query.where(Appointment.is_active == True)  # noqa: E712
    if family_member_id is not None:
        await _require_owned_active_family_member(
            db, family_member_id, current_user.id
        )
        query = query.where(Appointment.family_member_id == family_member_id)

    result = await db.execute(query)
    rows = list(result.scalars().all())
    names = await _family_names(db, rows, current_user.id)
    return [
        _to_response(
            a,
            family_member_name=names.get(a.family_member_id)
            if a.family_member_id
            else None,
        )
        for a in rows
    ]


@router.post("/", response_model=AppointmentResponse, status_code=201)
async def create_appointment(
    data: AppointmentCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    member_name = None
    if data.family_member_id is not None:
        member = await _require_owned_active_family_member(
            db, data.family_member_id, current_user.id
        )
        member_name = member.name

    appt = Appointment(
        user_id=current_user.id,
        family_member_id=data.family_member_id,
        title=data.title,
        scheduled_at=data.scheduled_at,
        notes=data.notes,
        remind_before_minutes=data.remind_before_minutes,
        is_active=True,
    )
    db.add(appt)
    await db.commit()
    await db.refresh(appt)
    return _to_response(appt, family_member_name=member_name)


@router.get("/{appointment_id}", response_model=AppointmentResponse)
async def get_appointment(
    appointment_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    appt = await _get_appointment(db, appointment_id, current_user.id)
    name = None
    if appt.family_member_id:
        names = await _family_names(db, [appt], current_user.id)
        name = names.get(appt.family_member_id)
    return _to_response(appt, family_member_name=name)


@router.put("/{appointment_id}", response_model=AppointmentResponse)
async def update_appointment(
    appointment_id: int,
    data: AppointmentUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    appt = await _get_appointment(db, appointment_id, current_user.id)

    if "family_member_id" in data.model_fields_set:
        if data.family_member_id is None:
            appt.family_member_id = None
        else:
            await _require_owned_active_family_member(
                db, data.family_member_id, current_user.id
            )
            appt.family_member_id = data.family_member_id

    if data.title is not None:
        appt.title = data.title
    if data.scheduled_at is not None:
        appt.scheduled_at = data.scheduled_at
    if "notes" in data.model_fields_set:
        appt.notes = data.notes
    if data.remind_before_minutes is not None:
        appt.remind_before_minutes = data.remind_before_minutes
    if data.is_active is not None:
        appt.is_active = data.is_active

    await db.commit()
    await db.refresh(appt)
    name = None
    if appt.family_member_id:
        names = await _family_names(db, [appt], current_user.id)
        name = names.get(appt.family_member_id)
    return _to_response(appt, family_member_name=name)


@router.delete("/{appointment_id}")
async def delete_appointment(
    appointment_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Soft-delete (is_active=False). Client cancels local notification."""
    appt = await _get_appointment(db, appointment_id, current_user.id)
    appt.is_active = False
    await db.commit()
    return {"message": "Appointment cancelled"}
