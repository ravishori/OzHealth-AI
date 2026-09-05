"""Async repository for medicine_enrichment_log."""
from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.medicine_enrichment_log import MedicineEnrichmentLog


class EnrichmentLogRepository:

    def __init__(self, db: AsyncSession):
        self.db = db

    async def log_change(
        self,
        *,
        medicine_id: int,
        field: str,
        old_value: Any,
        new_value: Any,
        source: str,
        confidence: float,
        run_id: uuid.UUID,
    ) -> None:
        self.db.add(MedicineEnrichmentLog(
            medicine_id   = medicine_id,
            field_updated = field,
            old_value     = None if old_value is None else str(old_value)[:8000],
            new_value     = None if new_value is None else str(new_value)[:8000],
            source        = source,
            confidence    = round(float(confidence), 2),
            run_id        = run_id,
        ))

    async def recent(self, *, limit: int = 50) -> list[MedicineEnrichmentLog]:
        rs = await self.db.execute(
            select(MedicineEnrichmentLog)
            .order_by(desc(MedicineEnrichmentLog.created_at))
            .limit(limit)
        )
        return list(rs.scalars().all())

    async def for_medicine(self, medicine_id: int) -> list[MedicineEnrichmentLog]:
        rs = await self.db.execute(
            select(MedicineEnrichmentLog)
            .where(MedicineEnrichmentLog.medicine_id == medicine_id)
            .order_by(desc(MedicineEnrichmentLog.created_at))
        )
        return list(rs.scalars().all())
