"""Add error_logs table previously created only via metadata.create_all.

Staging/production must not rely on SQLAlchemy create_all. This migration
brings the ORM ErrorLog model under Alembic so `upgrade head` is sufficient
on a clean database after 001→016.

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
        "error_logs",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("source", sa.String(50), nullable=False, server_default="backend"),
        sa.Column("severity", sa.String(20), nullable=False, server_default="error"),
        sa.Column("error_type", sa.String(200), nullable=True),
        sa.Column("message", sa.Text(), nullable=False, server_default=""),
        sa.Column("stack_trace", sa.Text(), nullable=True),
        sa.Column("http_method", sa.String(10), nullable=True),
        sa.Column("request_path", sa.String(500), nullable=True),
        sa.Column("correlation_id", sa.String(64), nullable=True),
        sa.Column("client_ip", sa.String(50), nullable=True),
        sa.Column("user_id", sa.Integer(), nullable=True),
        sa.Column("platform", sa.String(50), nullable=True),
        sa.Column("app_version", sa.String(50), nullable=True),
        sa.Column("screen", sa.String(200), nullable=True),
        sa.Column("context", sa.String(200), nullable=True),
        sa.Column("environment", sa.String(50), nullable=True),
        sa.Column("hostname", sa.String(200), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
    )
    op.create_index("ix_error_logs_created_at", "error_logs", ["created_at"])
    op.create_index("ix_error_logs_severity", "error_logs", ["severity"])


def downgrade() -> None:
    op.drop_index("ix_error_logs_severity", table_name="error_logs")
    op.drop_index("ix_error_logs_created_at", table_name="error_logs")
    op.drop_table("error_logs")
