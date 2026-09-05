"""
ePrescription model — stores validated eRx Script Exchange (NPDS) token results.

Security rules:
  • Raw token is NEVER persisted — only SHA-256 hash (64 hex chars).
  • Patient / prescriber / medicines columns use EncryptedText (Fernet AES).
  • token_hash has a UNIQUE constraint: prevents replay / double-submission.
  • token_last4 keeps the last 4 characters for audit / display only.

Additional models:
  EPrescriptionRefillReminder — per-medicine refill date alerts
  EPrescriptionShare          — share a prescription with a family member
"""
from sqlalchemy import (
    Column, Integer, String, Boolean, DateTime, ForeignKey, Text, UniqueConstraint,
)
from sqlalchemy.sql import func

from app.core.database import Base
from app.services.encryption_service import EncryptedText


class EPrescription(Base):
    __tablename__ = "e_prescriptions"

    id       = Column(Integer, primary_key=True, index=True)
    user_id  = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # ── Token (security) ──────────────────────────────────────────────────────
    # token_hash: SHA-256 hex digest of the raw token (never store the token itself)
    token_hash  = Column(String(64),  nullable=False, unique=True, index=True)
    token_last4 = Column(String(4),   nullable=True)   # last 4 chars for display

    # ── Provider / status ─────────────────────────────────────────────────────
    provider = Column(String(20), nullable=False, default="erx")   # erx | mock
    status   = Column(String(20), nullable=False, default="validated")
    # status values: validated | dispensed | expired | invalid

    # ── Prescription data (encrypted at rest) ─────────────────────────────────
    patient_name               = Column(EncryptedText, nullable=True)
    prescriber_name            = Column(EncryptedText, nullable=True)
    prescriber_provider_number = Column(EncryptedText, nullable=True)
    prescriber_practice        = Column(EncryptedText, nullable=True)
    medicines                  = Column(EncryptedText, nullable=True)  # JSON array

    # ── Dates ─────────────────────────────────────────────────────────────────
    prescription_date = Column(DateTime(timezone=True), nullable=True)
    expiry_date       = Column(DateTime(timezone=True), nullable=True)

    # ── TGA enrichment flag ───────────────────────────────────────────────────
    tga_enriched = Column(Boolean, default=False, nullable=False)

    # ── Auto-save flag ────────────────────────────────────────────────────────
    saved_to_records = Column(Boolean, default=False, nullable=False)

    # ── Timestamps ────────────────────────────────────────────────────────────
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())


# ─── Refill Reminders ──────────────────────────────────────────────────────────

class EPrescriptionRefillReminder(Base):
    """
    Per-medicine refill date reminder attached to an ePrescription.
    Users set a future date; the reminder worker will fire a push notification.
    """
    __tablename__ = "ep_refill_reminders"

    id            = Column(Integer, primary_key=True, index=True)
    ep_id         = Column(
        Integer,
        ForeignKey("e_prescriptions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id       = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    medicine_name = Column(String(255), nullable=False)
    refill_date   = Column(DateTime(timezone=True), nullable=False)
    note          = Column(String(500), nullable=True)
    is_notified   = Column(Boolean, default=False, nullable=False)
    created_at    = Column(DateTime(timezone=True), server_default=func.now())


# ─── Family Shares ────────────────────────────────────────────────────────────

class EPrescriptionShare(Base):
    """
    Records that a prescription has been shared with a specific family member.
    One row per (prescription, family_member) pair — enforced by UniqueConstraint.
    """
    __tablename__ = "ep_shares"

    id               = Column(Integer, primary_key=True, index=True)
    ep_id            = Column(
        Integer,
        ForeignKey("e_prescriptions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    owner_user_id    = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    family_member_id = Column(
        Integer,
        ForeignKey("family_members.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    family_member_name = Column(String(255), nullable=True)   # denormalised for display
    shared_at          = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        UniqueConstraint("ep_id", "family_member_id", name="uq_ep_shares_ep_member"),
    )
