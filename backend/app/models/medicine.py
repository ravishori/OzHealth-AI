"""
Medicine ORM model.

Only the columns this application reads/writes are declared here. The physical
table in PostgreSQL (built by Alembic migrations and the USA Medicines AI
Agent's reference loader) has many more columns — SQLAlchemy ignores those at
query time, which is intentional.
"""
from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    Integer,
    Numeric,
    String,
    Text,
)
from sqlalchemy.sql import func

from app.core.database import Base


class Medicine(Base):
    __tablename__ = "medicines"

    # ── Identity ─────────────────────────────────────────────────────────────
    id = Column(Integer, primary_key=True, index=True)
    name         = Column(String(500), nullable=False, index=True)
    generic_name = Column(String(500), nullable=True, index=True)

    # ── Reference fields (subset — full schema lives in the DB) ──────────────
    brand_names           = Column(Text, nullable=True)   # JSON array as text
    composition           = Column(Text, nullable=True)
    drug_class            = Column(String(255), nullable=True)
    dosage_forms          = Column(Text, nullable=True)   # JSON array as text
    standard_dosage       = Column(Text, nullable=True)
    side_effects          = Column(Text, nullable=True)
    interactions          = Column(Text, nullable=True)
    contraindications     = Column(Text, nullable=True)
    warnings              = Column(Text, nullable=True)
    storage_instructions  = Column(Text, nullable=True)
    barcode               = Column(String(100), nullable=True, index=True)
    tga_registered        = Column(Boolean, default=False)
    tga_artg_number       = Column(String(50),  nullable=True)
    schedule              = Column(String(50),  nullable=True)

    # Pre-existing reference columns in the DB (not all populated):
    dosage_form           = Column(Text,         nullable=True)
    strength              = Column(Text,         nullable=True)
    pack_size             = Column(String(100),  nullable=True)
    route                 = Column(Text,         nullable=True)
    pbs_code              = Column(String(50),   nullable=True)
    pbs_listing_date      = Column(Date, nullable=True)
    sponsor               = Column(String(255),  nullable=True)
    manufacturer          = Column(String(255),  nullable=True)
    release_type          = Column(String(100),  nullable=True)
    coating_type          = Column(String(100),  nullable=True)
    primary_source        = Column(String(50),   nullable=True)
    normalized_name       = Column(Text,         nullable=True)
    canonical_key         = Column(String(255),  nullable=True)
    pregnancy_category    = Column(String(10),   nullable=True)
    atc_code              = Column(String(20),   nullable=True)
    approval_date         = Column(DateTime(timezone=True), nullable=True)
    approval_type         = Column(String(100),  nullable=True)
    registration_status   = Column(String(100),  nullable=True)

    # ── NEW: self-learning cache + enrichment columns ────────────────────────
    # All defaulted at the DB level so existing rows backfill cleanly during the
    # Alembic migration. The application logic NEVER writes NULL to these.
    search_count       = Column(Integer, nullable=False, server_default="0")
    last_searched_at   = Column(DateTime(timezone=True), nullable=True)

    ai_enriched        = Column(Boolean, nullable=False, server_default="false")
    ai_enriched_at     = Column(DateTime(timezone=True), nullable=True)

    cache_version      = Column(String(50), nullable=True)
    popular_score      = Column(Numeric(10, 4), nullable=False, server_default="0")

    cache_hit_count    = Column(Integer, nullable=False, server_default="0")
    ai_hit_count       = Column(Integer, nullable=False, server_default="0")

    # ── Enrichment tracking (migration 014) ──────────────────────────────────
    amt_code              = Column(String(50),    nullable=True, index=True)
    brand_name            = Column(String(500),   nullable=True)
    active_ingredient     = Column(Text,          nullable=True)
    therapeutic_class     = Column(String(255),   nullable=True)
    uses                  = Column(Text,          nullable=True)
    pregnancy_warning     = Column(Text,          nullable=True)
    breastfeeding_warning = Column(Text,          nullable=True)
    consumer_information  = Column(Text,          nullable=True)
    image_url             = Column(String(1000),  nullable=True)
    last_verified         = Column(DateTime(timezone=True), nullable=True)
    data_source           = Column(String(255),   nullable=True)
    confidence_score      = Column(Numeric(3, 2), nullable=True)
    needs_manual_review   = Column(Boolean,       nullable=False, server_default="false")
    enrichment_attempts   = Column(Integer,       nullable=False, server_default="0")
    enrichment_attempted_at = Column(DateTime(timezone=True), nullable=True)

    # ── Bookkeeping ──────────────────────────────────────────────────────────
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
