"""add phone2 column to users table

Revision ID: 008
Revises: 007
Create Date: 2026-03-28
"""
from alembic import op
import sqlalchemy as sa

revision = '008'
down_revision = '007'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('phone2', sa.String(20), nullable=True))
    # Partial unique index so NULL values (most users) don't conflict
    op.create_index(
        'ix_users_phone2',
        'users',
        ['phone2'],
        unique=True,
        postgresql_where=sa.text('phone2 IS NOT NULL'),
    )


def downgrade() -> None:
    op.drop_index('ix_users_phone2', table_name='users')
    op.drop_column('users', 'phone2')
