"""HN-MEDMGMT-006 — medication dose / adherence history events.

A schedule defines what SHOULD happen; a dose event records what DID happen.
Does not mutate MedicationSchedule rows when a dose is taken/skipped/missed.
"""
from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    Index,
    CheckConstraint,
)
from sqlalchemy.sql import func

from app.core.database import Base


class MedicationDoseEvent(Base):
    __tablename__ = "medication_dose_events"
    __table_args__ = (
        UniqueConstraint(
            "medication_schedule_id",
            "scheduled_for",
            name="uq_med_dose_events_schedule_scheduled_for",
        ),
        CheckConstraint(
            "status IN ('taken', 'skipped', 'missed')",
            name="ck_med_dose_events_status",
        ),
        Index("ix_med_dose_events_user_recorded", "user_id", "recorded_at"),
        Index("ix_med_dose_events_schedule_id", "medication_schedule_id"),
        Index("ix_med_dose_events_user_scheduled", "user_id", "scheduled_for"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    medication_schedule_id = Column(
        Integer,
        ForeignKey("medication_schedules.id", ondelete="CASCADE"),
        nullable=False,
    )
    # Snapshot of schedule.family_member_id at record time (not auth authority).
    family_member_id = Column(
        Integer,
        ForeignKey("family_members.id", ondelete="SET NULL"),
        nullable=True,
    )
    # taken | skipped | missed
    status = Column(String(20), nullable=False)
    # Identity of the scheduled occurrence (client-supplied, validated).
    scheduled_for = Column(DateTime(timezone=True), nullable=False)
    # Server-controlled audit timestamp of when the status was recorded.
    recorded_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    created_at = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
