"""Add appointments table for HN-REM-010 (local appointment reminders).

Revision ID: 018
Revises: 017
Create Date: 2026-09-08
"""
from alembic import op
import sqlalchemy as sa

revision = "018"
down_revision = "017"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "appointments",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "family_member_id",
            sa.Integer(),
            sa.ForeignKey("family_members.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("title", sa.String(length=300), nullable=False),
        sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column(
            "remind_before_minutes",
            sa.Integer(),
            nullable=False,
            server_default="60",
        ),
        sa.Column(
            "is_active",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=True,
            server_default=sa.text("NOW()"),
        ),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_appointments_id", "appointments", ["id"])
    op.create_index("ix_appointments_user_id", "appointments", ["user_id"])
    op.create_index(
        "ix_appointments_user_scheduled",
        "appointments",
        ["user_id", "scheduled_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_appointments_user_scheduled", table_name="appointments")
    op.drop_index("ix_appointments_user_id", table_name="appointments")
    op.drop_index("ix_appointments_id", table_name="appointments")
    op.drop_table("appointments")
