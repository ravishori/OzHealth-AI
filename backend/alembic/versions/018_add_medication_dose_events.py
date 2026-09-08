"""Add medication_dose_events for HN-MEDMGMT-006 (adherence history).

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
        "medication_dose_events",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "medication_schedule_id",
            sa.Integer(),
            sa.ForeignKey("medication_schedules.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "family_member_id",
            sa.Integer(),
            sa.ForeignKey("family_members.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("scheduled_for", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "recorded_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('taken', 'skipped', 'missed')",
            name="ck_med_dose_events_status",
        ),
        sa.UniqueConstraint(
            "medication_schedule_id",
            "scheduled_for",
            name="uq_med_dose_events_schedule_scheduled_for",
        ),
    )
    op.create_index(
        "ix_medication_dose_events_id",
        "medication_dose_events",
        ["id"],
    )
    op.create_index(
        "ix_medication_dose_events_user_id",
        "medication_dose_events",
        ["user_id"],
    )
    op.create_index(
        "ix_med_dose_events_user_recorded",
        "medication_dose_events",
        ["user_id", "recorded_at"],
    )
    op.create_index(
        "ix_med_dose_events_schedule_id",
        "medication_dose_events",
        ["medication_schedule_id"],
    )
    op.create_index(
        "ix_med_dose_events_user_scheduled",
        "medication_dose_events",
        ["user_id", "scheduled_for"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_med_dose_events_user_scheduled",
        table_name="medication_dose_events",
    )
    op.drop_index(
        "ix_med_dose_events_schedule_id",
        table_name="medication_dose_events",
    )
    op.drop_index(
        "ix_med_dose_events_user_recorded",
        table_name="medication_dose_events",
    )
    op.drop_index(
        "ix_medication_dose_events_user_id",
        table_name="medication_dose_events",
    )
    op.drop_index(
        "ix_medication_dose_events_id",
        table_name="medication_dose_events",
    )
    op.drop_table("medication_dose_events")
