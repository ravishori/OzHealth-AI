"""Append-only audit log of every enrichment field change."""
from __future__ import annotations

import uuid

from sqlalchemy import (
    BigInteger,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func

from app.core.database import Base


class MedicineEnrichmentLog(Base):
    __tablename__ = "medicine_enrichment_log"

    log_id        = Column(BigInteger, primary_key=True, autoincrement=True)
    medicine_id   = Column(
        Integer,
        ForeignKey("medicines.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    field_updated = Column(String(100), nullable=False)
    old_value     = Column(Text, nullable=True)
    new_value     = Column(Text, nullable=True)
    source        = Column(String(50), nullable=False)
    confidence    = Column(Numeric(3, 2), nullable=False)
    created_at    = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    # All field updates from a single enrichment run share a run_id so the
    # ops UI can group them per-run.
    run_id        = Column(UUID(as_uuid=True), nullable=True, index=True,
                           default=uuid.uuid4)
