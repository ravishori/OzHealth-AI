"""Convert users encrypted columns from JSONB to TEXT.

The ORM model declares health_conditions, allergies, and lifestyle_preferences
as EncryptedText (a SQLAlchemy TypeDecorator extending Text).  The Fernet-
encrypted cipher text is a plain string, so the DB column must be TEXT, not JSONB.

The initial migration created them as JSONB by mistake.  asyncpg raises:
  DatatypeMismatchError: column "allergies" is of type jsonb
                         but expression is of type character varying

The view v_user_health_summary references health_conditions and allergies, so
it must be dropped before the ALTER and recreated afterwards.

Revision ID: 004
Revises:     003
"""

from alembic import op
import sqlalchemy as sa

revision = "004"
down_revision = "003"
branch_labels = None
depends_on = None

# ── Full definition of v_user_health_summary (recreated after ALTER) ──────────
_VIEW_DDL = """
CREATE OR REPLACE VIEW v_user_health_summary AS
SELECT
    u.id                AS user_id,
    u.name,
    u.email,
    u.phone,
    u.age,
    u.gender,
    u.blood_group,
    u.health_conditions,
    u.allergies,
    (SELECT COUNT(*) FROM family_members fm
     WHERE fm.user_id = u.id AND fm.is_active)                          AS family_member_count,
    (SELECT COUNT(*) FROM medical_records mr
     WHERE mr.user_id = u.id AND mr.is_active)                         AS medical_record_count,
    (SELECT COUNT(*) FROM prescriptions p
     WHERE p.user_id = u.id)                                            AS prescription_count,
    (SELECT COUNT(*) FROM medication_schedules ms
     WHERE ms.user_id = u.id AND ms.is_active)                         AS active_reminder_count,
    (SELECT COUNT(*) FROM emergency_contacts ec
     WHERE ec.user_id = u.id)                                           AS emergency_contact_count,
    (SELECT hm.value FROM health_metrics hm
     WHERE hm.user_id = u.id AND hm.metric_type = 'heart_rate'
     ORDER BY hm.recorded_at DESC LIMIT 1)                              AS latest_heart_rate,
    (SELECT hm.value FROM health_metrics hm
     WHERE hm.user_id = u.id AND hm.metric_type = 'blood_pressure_systolic'
     ORDER BY hm.recorded_at DESC LIMIT 1)                              AS latest_bp_systolic,
    (SELECT hm.value2 FROM health_metrics hm
     WHERE hm.user_id = u.id AND hm.metric_type = 'blood_pressure_systolic'
     ORDER BY hm.recorded_at DESC LIMIT 1)                              AS latest_bp_diastolic,
    (SELECT hm.value FROM health_metrics hm
     WHERE hm.user_id = u.id AND hm.metric_type = 'blood_sugar'
     ORDER BY hm.recorded_at DESC LIMIT 1)                              AS latest_blood_sugar,
    (SELECT hm.value FROM health_metrics hm
     WHERE hm.user_id = u.id AND hm.metric_type = 'weight'
     ORDER BY hm.recorded_at DESC LIMIT 1)                              AS latest_weight_kg,
    u.created_at,
    u.updated_at
FROM users u
WHERE u.is_active = TRUE
"""


def upgrade() -> None:
    # 1. Drop the view that references the columns we're altering
    op.execute(sa.text("DROP VIEW IF EXISTS v_user_health_summary"))

    # 2. Convert JSONB → TEXT (USING clause preserves any existing data)
    op.execute(sa.text("""
        ALTER TABLE users
            ALTER COLUMN health_conditions     TYPE TEXT USING health_conditions::TEXT,
            ALTER COLUMN allergies             TYPE TEXT USING allergies::TEXT,
            ALTER COLUMN lifestyle_preferences TYPE TEXT USING lifestyle_preferences::TEXT
    """))

    # 3. Recreate the view (now reads TEXT columns — works fine for display)
    op.execute(sa.text(_VIEW_DDL))


def downgrade() -> None:
    op.execute(sa.text("DROP VIEW IF EXISTS v_user_health_summary"))
    # Revert TEXT → JSONB.  Only safe if columns contain valid JSON (not encrypted).
    op.execute(sa.text("""
        ALTER TABLE users
            ALTER COLUMN health_conditions     TYPE JSONB USING health_conditions::JSONB,
            ALTER COLUMN allergies             TYPE JSONB USING allergies::JSONB,
            ALTER COLUMN lifestyle_preferences TYPE JSONB USING lifestyle_preferences::JSONB
    """))
    op.execute(sa.text(_VIEW_DDL))
