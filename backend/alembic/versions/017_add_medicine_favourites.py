"""Add medicine_favourites for HN-MED-009 (user bookmark only).

Revision ID: 017
Revises: 016
Create Date: 2026-09-07
"""
from alembic import op
import sqlalchemy as sa

revision = "017"
down_revision = "016"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "medicine_favourites",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "user_id",
            sa.Integer(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "medicine_id",
            sa.Integer(),
            sa.ForeignKey("medicines.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.UniqueConstraint(
            "user_id",
            "medicine_id",
            name="uq_medicine_favourites_user_medicine",
        ),
    )
    op.create_index(
        "ix_medicine_favourites_user_id",
        "medicine_favourites",
        ["user_id"],
    )
    op.create_index(
        "ix_medicine_favourites_medicine_id",
        "medicine_favourites",
        ["medicine_id"],
    )
    op.create_index(
        "ix_medicine_favourites_id",
        "medicine_favourites",
        ["id"],
    )


def downgrade() -> None:
    op.drop_index("ix_medicine_favourites_id", table_name="medicine_favourites")
    op.drop_index(
        "ix_medicine_favourites_medicine_id", table_name="medicine_favourites"
    )
    op.drop_index("ix_medicine_favourites_user_id", table_name="medicine_favourites")
    op.drop_table("medicine_favourites")
