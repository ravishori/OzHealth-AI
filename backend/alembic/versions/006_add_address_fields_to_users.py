"""add address fields to users

Revision ID: 006
Revises: 005
Create Date: 2026-03-26
"""
from alembic import op
import sqlalchemy as sa

revision = '006'
down_revision = '005'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('suburb', sa.String(100), nullable=True))
    op.add_column('users', sa.Column('city', sa.String(100), nullable=True))
    op.add_column('users', sa.Column('state', sa.String(100), nullable=True))
    op.add_column('users', sa.Column('postcode', sa.String(10), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'postcode')
    op.drop_column('users', 'state')
    op.drop_column('users', 'city')
    op.drop_column('users', 'suburb')
