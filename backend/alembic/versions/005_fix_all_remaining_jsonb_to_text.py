"""Fix all remaining JSONB columns that the ORM declares as Text/EncryptedText.

Every table column listed below is declared as Text (or EncryptedText which
extends Text) in the SQLAlchemy model but was created as JSONB by the initial
migration.  asyncpg refuses to write a VARCHAR/TEXT value into a JSONB column.

Columns fixed:
  family_members   : medical_conditions, allergies
  ai_conversations : messages           (EncryptedText — stores encrypted JSON)
  medication_schedules : times          (Text — stores JSON array of HH:MM strings)
  prescriptions    : extracted_medicines (EncryptedText — stores encrypted JSON)
  medicines        : brand_names, dosage_forms  (Text — stores JSON arrays)

Views dropped and recreated:
  v_active_reminders_today  — references medication_schedules.times
  v_medicine_search         — references medicines.brand_names, medicines.dosage_forms

Revision ID: 005
Revises:     004
"""

from alembic import op
import sqlalchemy as sa

revision = "005"
down_revision = "004"
branch_labels = None
depends_on = None

# ── View DDL (exact replicas of the existing views) ───────────────────────────

_V_ACTIVE_REMINDERS = """
CREATE OR REPLACE VIEW v_active_reminders_today AS
SELECT
    ms.id           AS schedule_id,
    ms.user_id,
    u.name          AS user_name,
    u.fcm_token,
    ms.family_member_id,
    fm.name         AS family_member_name,
    ms.medicine_name,
    ms.dosage,
    ms.frequency,
    ms.times,
    ms.instructions,
    ms.start_date,
    ms.end_date,
    ms.refill_date,
    ms.remaining_quantity,
    CASE
        WHEN ms.refill_date IS NOT NULL
         AND ms.refill_date <= CURRENT_DATE + INTERVAL '7 days' THEN TRUE
        ELSE FALSE
    END AS refill_due_soon
FROM medication_schedules ms
JOIN  users u  ON u.id  = ms.user_id
LEFT JOIN family_members fm ON fm.id = ms.family_member_id
WHERE ms.is_active = TRUE
  AND u.is_active  = TRUE
  AND u.fcm_token  IS NOT NULL
  AND (ms.start_date IS NULL OR ms.start_date <= CURRENT_DATE)
  AND (ms.end_date   IS NULL OR ms.end_date   >= CURRENT_DATE)
"""

_V_MEDICINE_SEARCH = """
CREATE OR REPLACE VIEW v_medicine_search AS
SELECT
    id,
    name,
    generic_name,
    brand_names,
    drug_class,
    dosage_forms,
    standard_dosage,
    schedule,
    tga_registered,
    tga_artg_number,
    pregnancy_category,
    atc_code,
    barcode,
    side_effects,
    contraindications,
    warnings,
    interactions,
    storage_instructions,
    CASE schedule
        WHEN 'S2' THEN 'Pharmacy Only'
        WHEN 'S3' THEN 'Pharmacist Only'
        WHEN 'S4' THEN 'Prescription Only'
        WHEN 'S8' THEN 'Controlled Drug'
        WHEN 'S9' THEN 'Prohibited Substance'
        ELSE 'Unscheduled (OTC)'
    END AS schedule_label,
    CASE pregnancy_category
        WHEN 'A'  THEN 'Safe — No fetal risk demonstrated'
        WHEN 'B1' THEN 'Limited data — Animal studies OK'
        WHEN 'B2' THEN 'Limited data — Animal studies inadequate'
        WHEN 'B3' THEN 'Limited data — Animal studies showed effects'
        WHEN 'C'  THEN 'Caution — Risk of fetal effects'
        WHEN 'D'  THEN 'Risk — Definite risk of fetal malformation'
        WHEN 'X'  THEN 'Contraindicated in pregnancy'
        ELSE NULL
    END AS pregnancy_category_label
FROM medicines m
"""


def upgrade() -> None:
    # ── 1. Drop ALL views that reference any column being altered ─────────────
    op.execute(sa.text("DROP VIEW IF EXISTS v_active_reminders_today"))
    op.execute(sa.text("DROP VIEW IF EXISTS v_medicine_search"))
    # v_prescription_medicines uses jsonb_array_elements(extracted_medicines).
    # That function requires JSONB; once the column becomes TEXT (encrypted
    # Fernet tokens), the view can never return meaningful data anyway.
    # It is dropped here and NOT recreated.
    op.execute(sa.text("DROP VIEW IF EXISTS v_prescription_medicines"))

    # ── 2. family_members ────────────────────────────────────────────────────
    op.execute(sa.text("""
        ALTER TABLE family_members
            ALTER COLUMN medical_conditions TYPE TEXT USING medical_conditions::TEXT,
            ALTER COLUMN allergies          TYPE TEXT USING allergies::TEXT
    """))

    # ── 3. ai_conversations.messages (EncryptedText stores Fernet tokens) ────
    op.execute(sa.text("""
        ALTER TABLE ai_conversations
            ALTER COLUMN messages TYPE TEXT USING messages::TEXT
    """))

    # ── 4. medication_schedules.times (JSON array of HH:MM strings) ──────────
    op.execute(sa.text("""
        ALTER TABLE medication_schedules
            ALTER COLUMN times TYPE TEXT USING times::TEXT
    """))

    # ── 5. prescriptions.extracted_medicines (EncryptedText) ─────────────────
    op.execute(sa.text("""
        ALTER TABLE prescriptions
            ALTER COLUMN extracted_medicines TYPE TEXT USING extracted_medicines::TEXT
    """))

    # ── 6. medicines.brand_names / dosage_forms (JSON arrays) ────────────────
    op.execute(sa.text("""
        ALTER TABLE medicines
            ALTER COLUMN brand_names  TYPE TEXT USING brand_names::TEXT,
            ALTER COLUMN dosage_forms TYPE TEXT USING dosage_forms::TEXT
    """))

    # ── 7. Recreate the two dropped views ────────────────────────────────────
    op.execute(sa.text(_V_ACTIVE_REMINDERS))
    op.execute(sa.text(_V_MEDICINE_SEARCH))


def downgrade() -> None:
    op.execute(sa.text("DROP VIEW IF EXISTS v_active_reminders_today"))
    op.execute(sa.text("DROP VIEW IF EXISTS v_medicine_search"))

    op.execute(sa.text("""
        ALTER TABLE family_members
            ALTER COLUMN medical_conditions TYPE JSONB USING medical_conditions::JSONB,
            ALTER COLUMN allergies          TYPE JSONB USING allergies::JSONB
    """))
    op.execute(sa.text("""
        ALTER TABLE ai_conversations
            ALTER COLUMN messages TYPE JSONB USING messages::JSONB
    """))
    op.execute(sa.text("""
        ALTER TABLE medication_schedules
            ALTER COLUMN times TYPE JSONB USING times::JSONB
    """))
    op.execute(sa.text("""
        ALTER TABLE prescriptions
            ALTER COLUMN extracted_medicines TYPE JSONB USING extracted_medicines::JSONB
    """))
    op.execute(sa.text("""
        ALTER TABLE medicines
            ALTER COLUMN brand_names  TYPE JSONB USING brand_names::JSONB,
            ALTER COLUMN dosage_forms TYPE JSONB USING dosage_forms::JSONB
    """))

    op.execute(sa.text(_V_ACTIVE_REMINDERS))
    op.execute(sa.text(_V_MEDICINE_SEARCH))
