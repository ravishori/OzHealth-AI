"""HN-MEDMGMT-006 — Medication dose / adherence history API.

Schedule (MedicationSchedule) = what SHOULD happen.
Dose event (MedicationDoseEvent) = what DID happen (taken / skipped / missed).

Ownership is always derived from the authenticated user + owned schedule.
Client-supplied user_id / owner_id are never accepted as authorization.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import select, func, and_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.log_decorator import LoggedAPIRoute
from app.models.user import User
from app.models.family_member import FamilyMember
from app.models.medication_schedule import MedicationSchedule
from app.models.medication_dose_event import MedicationDoseEvent
from app.schemas.medication_history import (
    MedicationDoseEventCreate,
    MedicationDoseEventResponse,
    MedicationAdherenceSummary,
)

router = APIRouter(route_class=LoggedAPIRoute)


async def _require_owned_active_family_member(
    db: AsyncSession,
    family_member_id: int,
    user_id: int,
) -> FamilyMember:
    """Same safe 404 semantics as reminders / health_metrics / prescriptions."""
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


async def _get_owned_schedule(
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
        # Do not disclose whether the id exists for another user.
        raise HTTPException(status_code=404, detail="Reminder not found")
    return schedule


async def _get_owned_event(
    db: AsyncSession, event_id: int, user_id: int
) -> MedicationDoseEvent:
    result = await db.execute(
        select(MedicationDoseEvent).where(
            MedicationDoseEvent.id == event_id,
            MedicationDoseEvent.user_id == user_id,
        )
    )
    event = result.scalar_one_or_none()
    if not event:
        raise HTTPException(status_code=404, detail="Dose event not found")
    return event


def _to_response(
    event: MedicationDoseEvent,
    *,
    medicine_name: Optional[str] = None,
    dosage: Optional[str] = None,
    duplicate: bool = False,
) -> MedicationDoseEventResponse:
    return MedicationDoseEventResponse(
        id=event.id,
        medication_schedule_id=event.medication_schedule_id,
        family_member_id=event.family_member_id,
        medicine_name=medicine_name,
        dosage=dosage,
        status=event.status,
        scheduled_for=event.scheduled_for,
        recorded_at=event.recorded_at,
        created_at=event.created_at,
        duplicate=duplicate,
    )


async def _medicine_labels(
    db: AsyncSession,
    schedule_ids: set[int],
    user_id: int,
) -> dict[int, tuple[str, Optional[str]]]:
    if not schedule_ids:
        return {}
    result = await db.execute(
        select(MedicationSchedule).where(
            MedicationSchedule.id.in_(schedule_ids),
            MedicationSchedule.user_id == user_id,
        )
    )
    schedules = result.scalars().all()
    return {
        s.id: (s.medicine_name, s.dosage) for s in schedules
    }


@router.post("/", response_model=MedicationDoseEventResponse)
async def create_dose_event(
    data: MedicationDoseEventCreate,
    response: Response,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Record TAKEN / SKIPPED / MISSED for an owned medication schedule occurrence.

    Idempotency: unique on (medication_schedule_id, scheduled_for).
    - Same status retry → 200 with duplicate=true (no second row).
    - Different status for same occurrence → 409 Conflict.
    Does not mutate the MedicationSchedule row.
    """
    schedule = await _get_owned_schedule(
        db, data.medication_schedule_id, current_user.id
    )
    medicine_name = schedule.medicine_name
    dosage = schedule.dosage
    family_member_id = schedule.family_member_id

    existing_result = await db.execute(
        select(MedicationDoseEvent).where(
            MedicationDoseEvent.medication_schedule_id == schedule.id,
            MedicationDoseEvent.scheduled_for == data.scheduled_for,
            MedicationDoseEvent.user_id == current_user.id,
        )
    )
    existing = existing_result.scalar_one_or_none()
    if existing is not None:
        if existing.status == data.status:
            response.status_code = 200
            return _to_response(
                existing,
                medicine_name=medicine_name,
                dosage=dosage,
                duplicate=True,
            )
        raise HTTPException(
            status_code=409,
            detail="Dose already recorded for this scheduled occurrence",
        )

    now = datetime.now(timezone.utc)
    event = MedicationDoseEvent(
        user_id=current_user.id,
        medication_schedule_id=schedule.id,
        family_member_id=family_member_id,
        status=data.status,
        scheduled_for=data.scheduled_for,
        recorded_at=now,
    )
    db.add(event)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raced = await db.execute(
            select(MedicationDoseEvent).where(
                MedicationDoseEvent.medication_schedule_id == schedule.id,
                MedicationDoseEvent.scheduled_for == data.scheduled_for,
                MedicationDoseEvent.user_id == current_user.id,
            )
        )
        raced_event = raced.scalar_one_or_none()
        if raced_event is not None and raced_event.status == data.status:
            response.status_code = 200
            return _to_response(
                raced_event,
                medicine_name=medicine_name,
                dosage=dosage,
                duplicate=True,
            )
        raise HTTPException(
            status_code=409,
            detail="Dose already recorded for this scheduled occurrence",
        )

    await db.refresh(event)
    response.status_code = 201
    return _to_response(
        event,
        medicine_name=medicine_name,
        dosage=dosage,
        duplicate=False,
    )


@router.get("/", response_model=list[MedicationDoseEventResponse])
async def list_dose_events(
    medication_schedule_id: Optional[int] = Query(None),
    family_member_id: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Owner-scoped history timeline, newest recorded_at first."""
    query = select(MedicationDoseEvent).where(
        MedicationDoseEvent.user_id == current_user.id
    )

    if medication_schedule_id is not None:
        # Prove schedule ownership before filtering (safe 404).
        await _get_owned_schedule(db, medication_schedule_id, current_user.id)
        query = query.where(
            MedicationDoseEvent.medication_schedule_id == medication_schedule_id
        )

    if family_member_id is not None:
        await _require_owned_active_family_member(
            db, family_member_id, current_user.id
        )
        query = query.where(
            MedicationDoseEvent.family_member_id == family_member_id
        )

    query = query.order_by(
        MedicationDoseEvent.recorded_at.desc(),
        MedicationDoseEvent.id.desc(),
    )
    result = await db.execute(query)
    events = list(result.scalars().all())
    labels = await _medicine_labels(
        db, {e.medication_schedule_id for e in events}, current_user.id
    )
    return [
        _to_response(
            e,
            medicine_name=(labels.get(e.medication_schedule_id) or (None, None))[0],
            dosage=(labels.get(e.medication_schedule_id) or (None, None))[1],
        )
        for e in events
    ]


@router.get("/summary", response_model=MedicationAdherenceSummary)
async def adherence_summary(
    medication_schedule_id: Optional[int] = Query(None),
    family_member_id: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Basic taken/skipped/missed counts + adherence % (taken/total)."""
    filters = [MedicationDoseEvent.user_id == current_user.id]

    if medication_schedule_id is not None:
        await _get_owned_schedule(db, medication_schedule_id, current_user.id)
        filters.append(
            MedicationDoseEvent.medication_schedule_id == medication_schedule_id
        )
    if family_member_id is not None:
        await _require_owned_active_family_member(
            db, family_member_id, current_user.id
        )
        filters.append(
            MedicationDoseEvent.family_member_id == family_member_id
        )

    result = await db.execute(
        select(
            MedicationDoseEvent.status,
            func.count(MedicationDoseEvent.id),
        )
        .where(and_(*filters))
        .group_by(MedicationDoseEvent.status)
    )
    counts = {row[0]: int(row[1]) for row in result.all()}
    taken = counts.get("taken", 0)
    skipped = counts.get("skipped", 0)
    missed = counts.get("missed", 0)
    total = taken + skipped + missed
    pct = round((taken / total) * 100, 1) if total > 0 else None
    return MedicationAdherenceSummary(
        taken=taken,
        skipped=skipped,
        missed=missed,
        total=total,
        adherence_percent=pct,
    )


@router.get("/{event_id}", response_model=MedicationDoseEventResponse)
async def get_dose_event(
    event_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = await _get_owned_event(db, event_id, current_user.id)
    labels = await _medicine_labels(
        db, {event.medication_schedule_id}, current_user.id
    )
    name, dosage = labels.get(event.medication_schedule_id, (None, None))
    return _to_response(event, medicine_name=name, dosage=dosage)


@router.delete("/{event_id}", status_code=204)
async def delete_dose_event(
    event_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Owner-scoped delete only. Cross-user → 404."""
    event = await _get_owned_event(db, event_id, current_user.id)
    await db.delete(event)
    await db.commit()
    return None
