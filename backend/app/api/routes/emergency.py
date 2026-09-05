from fastapi import APIRouter, Depends, HTTPException
from app.core.log_decorator import LoggedAPIRoute
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
import asyncio

from app.core.database import get_db
from app.core.deps import get_current_user
from app.models.user import User
from app.models.emergency_contact import EmergencyContact
from app.schemas.emergency import (
    EmergencyContactCreate,
    EmergencyContactResponse,
    SOSRequest,
    SOSResponse,
)
from app.services.notification_service import NotificationService

router = APIRouter(route_class=LoggedAPIRoute)


@router.get("/contacts", response_model=list[EmergencyContactResponse])
async def list_contacts(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(EmergencyContact)
        .where(EmergencyContact.user_id == current_user.id)
        .order_by(EmergencyContact.is_primary.desc())
    )
    return result.scalars().all()


@router.post("/contacts", response_model=EmergencyContactResponse, status_code=201)
async def add_contact(
    data: EmergencyContactCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # If new contact is primary, clear previous primary
    if data.is_primary:
        existing = await db.execute(
            select(EmergencyContact).where(
                EmergencyContact.user_id == current_user.id,
                EmergencyContact.is_primary == True,
            )
        )
        for c in existing.scalars().all():
            c.is_primary = False

    contact = EmergencyContact(
        user_id=current_user.id,
        name=data.name,
        phone=data.phone,
        relationship=data.relationship,
        is_primary=data.is_primary,
    )
    db.add(contact)
    await db.commit()
    await db.refresh(contact)
    return contact


@router.delete("/contacts/{contact_id}")
async def delete_contact(
    contact_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(EmergencyContact).where(
            EmergencyContact.id == contact_id,
            EmergencyContact.user_id == current_user.id,
        )
    )
    contact = result.scalar_one_or_none()
    if not contact:
        raise HTTPException(status_code=404, detail="Contact not found")
    await db.delete(contact)
    await db.commit()
    return {"message": "Contact deleted"}


@router.post("/sos", response_model=SOSResponse)
async def trigger_sos(
    req: SOSRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    SOS (dial-first honesty mode).

    Records GPS and contact list for the user, but does NOT claim SMS/push
    delivery to contacts until a real notifier is integrated. Automatic
    contact SMS/FCM is not enabled (P0 mock removal).
    """
    result = await db.execute(
        select(EmergencyContact).where(EmergencyContact.user_id == current_user.id)
    )
    contacts = result.scalars().all()

    location_url: Optional[str] = None
    if req.latitude and req.longitude:
        location_url = (
            f"https://maps.google.com/?q={req.latitude},{req.longitude}"
        )

    import logging
    log = logging.getLogger(__name__)
    log.warning(
        "[SOS] dial-first mode user_id=%s contacts=%d location_set=%s",
        current_user.id,
        len(contacts),
        bool(location_url),
    )

    # Optional confirmation push to the *user's own* device only — not contacts.
    if current_user.fcm_token:
        await asyncio.gather(
            NotificationService.send(
                current_user.fcm_token,
                title="SOS recorded",
                body="Call 000 for emergencies. Contacts were not auto-notified.",
                data={"type": "sos_confirmation"},
            ),
            return_exceptions=True,
        )

    n_contacts = len(contacts)
    if n_contacts == 0:
        msg = (
            "SOS recorded. No emergency contacts saved. "
            "Call 000 now if this is an emergency."
        )
    else:
        msg = (
            f"SOS recorded with your location. "
            f"{n_contacts} contact(s) are listed for you to call manually — "
            f"they were NOT automatically notified by SMS or push. Call 000 if needed."
        )

    return SOSResponse(
        success=True,
        contacts_notified=0,  # honest: no auto-notify until SMS/FCM-to-contacts ships
        message=msg,
        location_url=location_url,
    )
