"""Add medicine cache columns + medicine_search_cache table.

Revision ID: 013_medicine_cache
Revises:     012_eprescription_features
Create Date: 2026-05-19

Adds the self-learning enrichment layer:
  - 8 new columns on `medicines` (search_count, ai_enriched, popular_score, …)
  - new table `medicine_search_cache` keyed by normalized_query
  - supporting indexes
  - pgcrypto extension (for gen_random_uuid()) if not already present
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision      = "013_medicine_cache"
down_revision = "012"
branch_labels = None
depends_on    = None


def upgrade() -> None:
    # ── Required extension for gen_random_uuid() default on cache_id ─────────
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    # ── New columns on medicines ─────────────────────────────────────────────
    op.add_column("medicines",
        sa.Column("search_count",    sa.Integer(),  nullable=False, server_default="0"))
    op.add_column("medicines",
        sa.Column("last_searched_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("medicines",
        sa.Column("ai_enriched",     sa.Boolean(),  nullable=False, server_default=sa.text("false")))
    op.add_column("medicines",
        sa.Column("ai_enriched_at",  sa.DateTime(timezone=True), nullable=True))
    op.add_column("medicines",
        sa.Column("cache_version",   sa.String(50), nullable=True))
    op.add_column("medicines",
        sa.Column("popular_score",   sa.Numeric(10, 4), nullable=False, server_default="0"))
    op.add_column("medicines",
        sa.Column("cache_hit_count", sa.Integer(),  nullable=False, server_default="0"))
    op.add_column("medicines",
        sa.Column("ai_hit_count",    sa.Integer(),  nullable=False, server_default="0"))

    # Helpful index for /medicine/popular ordering.
    op.create_index(
        "ix_medicines_popular_score",
        "medicines",
        [sa.text("popular_score DESC")],
    )
    op.create_index("ix_medicines_search_count",     "medicines", ["search_count"])
    op.create_index("ix_medicines_last_searched_at", "medicines", ["last_searched_at"])

    # ── New table: medicine_search_cache ─────────────────────────────────────
    op.create_table(
        "medicine_search_cache",
        sa.Column("cache_id", sa.dialects.postgresql.UUID(as_uuid=True),
                  primary_key=True,
                  server_default=sa.text("gen_random_uuid()")),
        sa.Column("medicine_id", sa.Integer(),
                  sa.ForeignKey("medicines.id", ondelete="SET NULL"),
                  nullable=True),
        sa.Column("query_text",       sa.Text(),     nullable=False),
        sa.Column("normalized_query", sa.String(255), nullable=False),
        sa.Column("ai_response",      sa.dialects.postgresql.JSONB(),
                  nullable=False, server_default=sa.text("'{}'::jsonb")),
        sa.Column("prompt_version",   sa.String(30), nullable=True),
        sa.Column("cache_expiry",     sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at",       sa.DateTime(timezone=True),
                  nullable=False, server_default=sa.text("now()")),
        sa.Column("hit_count",        sa.Integer(),  nullable=False, server_default="0"),
        sa.Column("last_hit_at",      sa.DateTime(timezone=True), nullable=True),
        sa.Column("source_type",      sa.String(20), nullable=False, server_default="ai"),
        sa.Column("source_priority",  sa.Integer(),  nullable=False, server_default="100"),
        sa.Column("needs_refresh",    sa.Boolean(),  nullable=False, server_default=sa.text("false")),
        sa.UniqueConstraint("normalized_query", name="uq_msc_normalized_query"),
    )

    op.create_index("ix_medicine_search_cache_medicine_id",
                    "medicine_search_cache", ["medicine_id"])
    op.create_index("ix_msc_normalized_valid",
                    "medicine_search_cache", ["normalized_query", "cache_expiry"])
    op.create_index("ix_msc_hit_count_desc",
                    "medicine_search_cache", [sa.text("hit_count DESC")])
    op.create_index("ix_msc_needs_refresh",
                    "medicine_search_cache", ["needs_refresh", "cache_expiry"])
    op.create_index("ix_medicine_search_cache_cache_expiry",
                    "medicine_search_cache", ["cache_expiry"])


def downgrade() -> None:
    op.drop_index("ix_medicine_search_cache_cache_expiry", table_name="medicine_search_cache")
    op.drop_index("ix_msc_needs_refresh",        table_name="medicine_search_cache")
    op.drop_index("ix_msc_hit_count_desc",       table_name="medicine_search_cache")
    op.drop_index("ix_msc_normalized_valid",     table_name="medicine_search_cache")
    op.drop_index("ix_medicine_search_cache_medicine_id",
                  table_name="medicine_search_cache")
    op.drop_table("medicine_search_cache")

    op.drop_index("ix_medicines_last_searched_at", table_name="medicines")
    op.drop_index("ix_medicines_search_count",     table_name="medicines")
    op.drop_index("ix_medicines_popular_score",    table_name="medicines")

    for col in (
        "ai_hit_count", "cache_hit_count", "popular_score",
        "cache_version", "ai_enriched_at", "ai_enriched",
        "last_searched_at", "search_count",
    ):
        op.drop_column("medicines", col)
