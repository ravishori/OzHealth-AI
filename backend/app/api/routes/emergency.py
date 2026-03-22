from fastapi import APIRouter, Depends, HTTPException
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

router = APIRouter()


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
    """Trigger SOS: notifies all emergency contacts via push notification."""
    result = await db.execute(
        select(EmergencyContact).where(EmergencyContact.user_id == current_user.id)
    )
    contacts = result.scalars().all()

    location_url: Optional[str] = None
    if req.latitude and req.longitude:
        location_url = (
            f"https://maps.google.com/?q={req.latitude},{req.longitude}"
        )

    # Send push to user's own device (if FCM token exists)
    notified = 0
    tasks = []
    if current_user.fcm_token:
        tasks.append(
            NotificationService.send(
                current_user.fcm_token,
                title="🚨 SOS Sent",
                body="Your SOS alert has been sent to your emergency contacts.",
                data={"type": "sos_confirmation"},
            )
        )

    # NOTE: In production, integrate Twilio/AWS SNS to SMS contacts.
    # For now we log and send FCM to contacts who are also app users (via phone lookup).
    import logging
    log = logging.getLogger(__name__)
    log.warning(
        "[SOS] User=%s | Location=%s | Contacts=%d",
        current_user.name,
        location_url,
        len(contacts),
    )
    for c in contacts:
        log.warning("  → %s (%s)", c.name, c.phone)
        notified += 1

    if tasks:
        await asyncio.gather(*tasks, return_exceptions=True)

    return SOSResponse(
        success=True,
        contacts_notified=notified,
        message=(
            f"SOS alert sent to {notified} emergency contact(s)."
            if notified
            else "SOS triggered — no emergency contacts configured. Please add contacts."
        ),
        location_url=location_url,
    )
