"""012 — ePrescription extended features

Adds:
  • e_prescriptions.saved_to_records  BOOLEAN DEFAULT FALSE
  • ep_refill_reminders               table
  • ep_shares                         table

Revision ID: 012
Revises: 011
"""
from alembic import op
import sqlalchemy as sa

revision  = "012"
down_revision = "011"
branch_labels = None
depends_on    = None


def upgrade() -> None:
    # ── saved_to_records flag on main table ───────────────────────────────────
    op.add_column(
        "e_prescriptions",
        sa.Column("saved_to_records", sa.Boolean(), nullable=False, server_default="false"),
    )

    # ── ep_refill_reminders ───────────────────────────────────────────────────
    op.create_table(
        "ep_refill_reminders",
        sa.Column("id",            sa.Integer(),                     primary_key=True),
        sa.Column("ep_id",         sa.Integer(),                     nullable=False),
        sa.Column("user_id",       sa.Integer(),                     nullable=False),
        sa.Column("medicine_name", sa.String(255),                   nullable=False),
        sa.Column("refill_date",   sa.DateTime(timezone=True),       nullable=False),
        sa.Column("note",          sa.String(500),                   nullable=True),
        sa.Column("is_notified",   sa.Boolean(),                     nullable=False, server_default="false"),
        sa.Column("created_at",    sa.DateTime(timezone=True),       server_default=sa.text("now()")),
        sa.ForeignKeyConstraint(["ep_id"],   ["e_prescriptions.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"],            ondelete="CASCADE"),
    )
    op.create_index("ix_ep_refill_reminders_ep_id",   "ep_refill_reminders", ["ep_id"])
    op.create_index("ix_ep_refill_reminders_user_id", "ep_refill_reminders", ["user_id"])

    # ── ep_shares ─────────────────────────────────────────────────────────────
    op.create_table(
        "ep_shares",
        sa.Column("id",                 sa.Integer(),               primary_key=True),
        sa.Column("ep_id",              sa.Integer(),               nullable=False),
        sa.Column("owner_user_id",      sa.Integer(),               nullable=False),
        sa.Column("family_member_id",   sa.Integer(),               nullable=False),
        sa.Column("family_member_name", sa.String(255),             nullable=True),
        sa.Column("shared_at",          sa.DateTime(timezone=True), server_default=sa.text("now()")),
        sa.ForeignKeyConstraint(["ep_id"],            ["e_prescriptions.id"],   ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["owner_user_id"],    ["users.id"],              ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["family_member_id"], ["family_members.id"],    ondelete="CASCADE"),
        sa.UniqueConstraint("ep_id", "family_member_id", name="uq_ep_shares_ep_member"),
    )
    op.create_index("ix_ep_shares_ep_id",          "ep_shares", ["ep_id"])
    op.create_index("ix_ep_shares_owner_user_id",  "ep_shares", ["owner_user_id"])
    op.create_index("ix_ep_shares_family_member_id", "ep_shares", ["family_member_id"])


def downgrade() -> None:
    op.drop_table("ep_shares")
    op.drop_table("ep_refill_reminders")
    op.drop_column("e_prescriptions", "saved_to_records")
