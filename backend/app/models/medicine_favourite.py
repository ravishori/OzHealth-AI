"""HN-MED-009 — per-user medicine favourites (bookmark only; not a prescription)."""
from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Integer,
    UniqueConstraint,
    Index,
)
from sqlalchemy.sql import func

from app.core.database import Base


class MedicineFavourite(Base):
    __tablename__ = "medicine_favourites"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "medicine_id",
            name="uq_medicine_favourites_user_medicine",
        ),
        Index("ix_medicine_favourites_user_id", "user_id"),
        Index("ix_medicine_favourites_medicine_id", "medicine_id"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    medicine_id = Column(
        Integer,
        ForeignKey("medicines.id", ondelete="CASCADE"),
        nullable=False,
    )
    created_at = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
