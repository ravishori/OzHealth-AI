"""Expand otps.purpose check constraint to include contact_change

Revision ID: 009
Revises: 008
Create Date: 2026-03-28 00:00:00.000000

Changes:
  - DROP   otps_purpose_check  (allowed: auth | register | reset)
  - CREATE otps_purpose_check  (allowed: auth | register | reset | contact_change)

The contact_change purpose was added to support the OTP-verified
email/phone change flow in /users/me/request-contact-change.
"""

from alembic import op
import sqlalchemy as sa

revision = '009'
down_revision = '008'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Drop the old restrictive check constraint
    op.execute(sa.text(
        "ALTER TABLE otps DROP CONSTRAINT IF EXISTS otps_purpose_check"
    ))

    # Add the expanded constraint that includes contact_change
    op.execute(sa.text("""
        ALTER TABLE otps
        ADD CONSTRAINT otps_purpose_check
        CHECK (purpose IN ('auth', 'register', 'reset', 'contact_change'))
    """))


def downgrade() -> None:
    # Revert to the original three-value constraint
    # NOTE: any rows with purpose='contact_change' will block this downgrade.
    op.execute(sa.text(
        "ALTER TABLE otps DROP CONSTRAINT IF EXISTS otps_purpose_check"
    ))
    op.execute(sa.text("""
        ALTER TABLE otps
        ADD CONSTRAINT otps_purpose_check
        CHECK (purpose IN ('auth', 'register', 'reset'))
    """))
