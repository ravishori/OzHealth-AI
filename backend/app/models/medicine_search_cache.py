"""
Persistent medicine-query cache.

Every successful resolution of `GET /api/medicine/search?q=...` writes one row
here, keyed by the normalised query. Subsequent searches with any equivalent
spelling (panadol / Panadol / PANADOL 500MG) reuse the AI-generated payload
without touching the LLM.

Row lifecycle
─────────────
1. Search arrives, normaliser produces `normalized_query`.
2. Lookup by (normalized_query, status=valid).
3. Hit  → bump hit_count, last_hit_at; return ai_response verbatim.
4. Miss → resolve via local DB or external sources, call AI, INSERT row with
          cache_expiry = now + TTL_for_popularity_band.
5. Nightly worker refreshes the top-N most-hit rows whose cache_expiry is in
   the next 24h, so traffic never sees a cold cache for popular drugs.
"""
from __future__ import annotations

import uuid

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.sql import func

from app.core.database import Base


class MedicineSearchCache(Base):
    """Persistent cache of AI-enriched medicine responses, keyed by query."""

    __tablename__ = "medicine_search_cache"

    cache_id = Column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
        server_default=func.gen_random_uuid(),
    )

    # Foreign key into medicines. Nullable so we can cache "looked but found
    # nothing" answers too (negative caching avoids re-hammering external
    # sources for typos).
    medicine_id = Column(
        Integer,
        ForeignKey("medicines.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    # The exact text the user typed (audit / debug).
    query_text       = Column(Text, nullable=False)
    # The normalised form used for the actual lookup. UNIQUE so concurrent
    # inserts collapse via ON CONFLICT.
    normalized_query = Column(String(255), nullable=False, unique=True, index=True)

    # The full AI payload. JSONB so we can query individual fields without
    # deserialising the whole blob.
    ai_response   = Column(JSONB, nullable=False, server_default="{}")
    prompt_version = Column(String(30), nullable=True)

    # Expiry / freshness.
    cache_expiry  = Column(DateTime(timezone=True), nullable=False, index=True)
    created_at    = Column(DateTime(timezone=True), nullable=False,
                           server_default=func.now())

    # Hit counters.
    hit_count   = Column(Integer, nullable=False, server_default="0")
    last_hit_at = Column(DateTime(timezone=True), nullable=True)

    # Where this row's data came from: 'local' | 'ai' | 'tga' | 'pbs' |
    # 'artg' | 'composite'. Used by analytics to score source quality.
    source_type     = Column(String(20), nullable=False, server_default="ai")
    # 1 = highest authority (e.g. TGA). Used as a tiebreaker when multiple
    # sources contribute to the same medicine_id.
    source_priority = Column(Integer, nullable=False, server_default="100")

    # Set TRUE by the nightly worker when it identifies a row that should be
    # refreshed even though it hasn't expired yet (popularity bump, prompt
    # version change, etc.).
    needs_refresh = Column(Boolean, nullable=False, server_default="false")

    __table_args__ = (
        # Hottest lookup: "is this query in cache and still valid?"
        Index("ix_msc_normalized_valid", "normalized_query", "cache_expiry"),
        # Analytics: most-popular cache entries.
        Index("ix_msc_hit_count_desc", hit_count.desc()),
        # Worker queue: rows up for refresh.
        Index("ix_msc_needs_refresh", "needs_refresh", "cache_expiry"),
    )
