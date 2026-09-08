"""HN-REM-010 — appointment reminder persistence."""
from sqlalchemy import (
    Column,
    Integer,
    String,
    ForeignKey,
    Text,
    DateTime,
    Boolean,
    Index,
)
from sqlalchemy.sql import func

from app.core.database import Base


class Appointment(Base):
    __tablename__ = "appointments"
    __table_args__ = (
        Index("ix_appointments_user_scheduled", "user_id", "scheduled_at"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    family_member_id = Column(
        Integer,
        ForeignKey("family_members.id", ondelete="SET NULL"),
        nullable=True,
    )
    title = Column(String(300), nullable=False)
    scheduled_at = Column(DateTime(timezone=True), nullable=False)
    notes = Column(Text, nullable=True)
    # Minutes before scheduled_at to fire the local reminder (0 = at time).
    remind_before_minutes = Column(Integer, nullable=False, default=60)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
