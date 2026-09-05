"""Add e_prescriptions table for the ePrescription (eRx / MediSecure) feature.

Security design:
  • token_hash  — SHA-256 hex; UNIQUE constraint prevents replay attacks.
  • token_last4 — last 4 chars of the original token (for display / audit only).
  • All patient / prescriber / medicine columns use TEXT so that the application-
    layer EncryptedText (Fernet AES-128-CBC) handles field-level encryption.
  • Raw token is NEVER stored at any layer.

Revision ID: 011
Revises: 010
Create Date: 2026-03-29
"""

from alembic import op
import sqlalchemy as sa

revision      = "011"
down_revision = "010"
branch_labels = None
depends_on    = None


def upgrade() -> None:
    op.create_table(
        "e_prescriptions",
        sa.Column("id",       sa.Integer, primary_key=True, index=True),
        sa.Column(
            "user_id",
            sa.Integer,
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),

        # ── Token (security) ──────────────────────────────────────────────────
        sa.Column("token_hash",  sa.String(64),  nullable=False),
        sa.Column("token_last4", sa.String(4),   nullable=True),

        # ── Provider / status ──────────────────────────────────────────────────
        sa.Column("provider", sa.String(20), nullable=False, server_default="erx"),
        sa.Column("status",   sa.String(20), nullable=False, server_default="validated"),

        # ── Prescription data (TEXT — encrypted by app layer) ─────────────────
        sa.Column("patient_name",               sa.Text, nullable=True),
        sa.Column("prescriber_name",            sa.Text, nullable=True),
        sa.Column("prescriber_provider_number", sa.Text, nullable=True),
        sa.Column("prescriber_practice",        sa.Text, nullable=True),
        sa.Column("medicines",                  sa.Text, nullable=True),  # JSON array

        # ── Dates ─────────────────────────────────────────────────────────────
        sa.Column("prescription_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expiry_date",       sa.DateTime(timezone=True), nullable=True),

        # ── TGA enrichment ────────────────────────────────────────────────────
        sa.Column("tga_enriched", sa.Boolean, nullable=False, server_default="false"),

        # ── Timestamps ────────────────────────────────────────────────────────
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("NOW()"),
            nullable=False,
        ),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
    )

    # UNIQUE on token_hash prevents replay / double-submission
    op.create_unique_constraint(
        "uq_e_prescriptions_token_hash",
        "e_prescriptions",
        ["token_hash"],
    )

    # Index for fast lookup by token_hash (used on every validate call)
    op.create_index(
        "ix_e_prescriptions_token_hash",
        "e_prescriptions",
        ["token_hash"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index("ix_e_prescriptions_token_hash", table_name="e_prescriptions")
    op.drop_constraint("uq_e_prescriptions_token_hash", "e_prescriptions")
    op.drop_table("e_prescriptions")
