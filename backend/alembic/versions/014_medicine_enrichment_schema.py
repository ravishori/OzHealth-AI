"""Medicine enrichment columns + medicine_enrichment_log table.

Revision ID: 014_medicine_enrichment
Revises:     013_medicine_cache
Create Date: 2026-05-19

Adds the columns the AU healthcare enrichment pipeline needs to track
provenance and confidence, plus an append-only log of every field-level
update so changes are auditable.
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision      = "014_medicine_enrichment"
down_revision = "013_medicine_cache"
branch_labels = None
depends_on    = None


def upgrade() -> None:
    # ── Add new tracking columns on `medicines` (idempotent) ────────────────
    # We use IF NOT EXISTS via raw SQL because the table predates Alembic and
    # production DBs may already have some of these columns from earlier
    # manual SQL work.
    op.execute("""
        ALTER TABLE medicines
            ADD COLUMN IF NOT EXISTS amt_code              VARCHAR(50),
            ADD COLUMN IF NOT EXISTS brand_name            VARCHAR(500),
            ADD COLUMN IF NOT EXISTS active_ingredient     TEXT,
            ADD COLUMN IF NOT EXISTS therapeutic_class     VARCHAR(255),
            ADD COLUMN IF NOT EXISTS uses                  TEXT,
            ADD COLUMN IF NOT EXISTS pregnancy_warning     TEXT,
            ADD COLUMN IF NOT EXISTS breastfeeding_warning TEXT,
            ADD COLUMN IF NOT EXISTS consumer_information  TEXT,
            ADD COLUMN IF NOT EXISTS image_url             VARCHAR(1000),
            ADD COLUMN IF NOT EXISTS last_verified         TIMESTAMPTZ,
            ADD COLUMN IF NOT EXISTS data_source           VARCHAR(255),
            ADD COLUMN IF NOT EXISTS confidence_score      NUMERIC(3, 2),
            ADD COLUMN IF NOT EXISTS needs_manual_review   BOOLEAN NOT NULL DEFAULT FALSE,
            ADD COLUMN IF NOT EXISTS enrichment_attempts   INTEGER NOT NULL DEFAULT 0,
            ADD COLUMN IF NOT EXISTS enrichment_attempted_at TIMESTAMPTZ
    """)

    op.create_index("ix_medicines_amt_code",
                    "medicines", ["amt_code"], if_not_exists=True)
    op.create_index("ix_medicines_needs_review",
                    "medicines", ["needs_manual_review"], if_not_exists=True,
                    postgresql_where=sa.text("needs_manual_review = TRUE"))
    op.create_index("ix_medicines_last_verified",
                    "medicines", ["last_verified"], if_not_exists=True)

    # ── medicine_enrichment_log (append-only audit) ──────────────────────────
    op.create_table(
        "medicine_enrichment_log",
        sa.Column("log_id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column("medicine_id", sa.Integer(),
                  sa.ForeignKey("medicines.id", ondelete="CASCADE"),
                  nullable=False, index=True),
        sa.Column("field_updated", sa.String(100), nullable=False),
        sa.Column("old_value",     sa.Text(),       nullable=True),
        sa.Column("new_value",     sa.Text(),       nullable=True),
        sa.Column("source",        sa.String(50),   nullable=False),
        sa.Column("confidence",    sa.Numeric(3, 2), nullable=False),
        sa.Column("created_at",    sa.DateTime(timezone=True),
                  nullable=False, server_default=sa.text("now()")),
        sa.Column("run_id",        sa.dialects.postgresql.UUID(as_uuid=True),
                  nullable=True, index=True),
    )

    op.create_index("ix_mel_field_source",
                    "medicine_enrichment_log", ["field_updated", "source"])
    op.create_index("ix_mel_created_at_desc",
                    "medicine_enrichment_log", [sa.text("created_at DESC")])


def downgrade() -> None:
    op.drop_index("ix_mel_created_at_desc", table_name="medicine_enrichment_log")
    op.drop_index("ix_mel_field_source",    table_name="medicine_enrichment_log")
    op.drop_table("medicine_enrichment_log")

    op.drop_index("ix_medicines_last_verified", table_name="medicines",
                  if_exists=True)
    op.drop_index("ix_medicines_needs_review",  table_name="medicines",
                  if_exists=True)
    op.drop_index("ix_medicines_amt_code",      table_name="medicines",
                  if_exists=True)

    op.execute("""
        ALTER TABLE medicines
            DROP COLUMN IF EXISTS enrichment_attempted_at,
            DROP COLUMN IF EXISTS enrichment_attempts,
            DROP COLUMN IF EXISTS needs_manual_review,
            DROP COLUMN IF EXISTS confidence_score,
            DROP COLUMN IF EXISTS data_source,
            DROP COLUMN IF EXISTS last_verified,
            DROP COLUMN IF EXISTS image_url,
            DROP COLUMN IF EXISTS consumer_information,
            DROP COLUMN IF EXISTS breastfeeding_warning,
            DROP COLUMN IF EXISTS pregnancy_warning,
            DROP COLUMN IF EXISTS uses,
            DROP COLUMN IF EXISTS therapeutic_class,
            DROP COLUMN IF EXISTS active_ingredient,
            DROP COLUMN IF EXISTS brand_name,
            DROP COLUMN IF EXISTS amt_code
    """)
