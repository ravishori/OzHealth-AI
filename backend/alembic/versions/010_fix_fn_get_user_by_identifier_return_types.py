"""Fix stored procedure return types: JSONB columns changed to TEXT in migrations
004 and 005, but 6 stored procedures still declared those columns as JSONB in
their RETURNS TABLE, causing DatatypeMismatchError on every call.

Root cause:
  Migration 004 changed users.health_conditions / allergies → TEXT.
  Migration 005 changed family_members.medical_conditions / allergies,
  ai_conversations.messages, medication_schedules.times, and
  medicines.brand_names → TEXT.
  None of those migrations updated the stored procedures.

asyncpg error seen in production:
  DatatypeMismatchError: structure of query does not match function result type
  DETAIL: Returned type text does not match expected type jsonb in column
  "health_conditions" (position 8).

Functions fixed (all DROP + CREATE because PostgreSQL forbids changing RETURNS):
  1. fn_get_user_by_identifier  — health_conditions TEXT, allergies TEXT
  2. fn_get_user_by_id          — health_conditions TEXT, allergies TEXT
  3. fn_get_family_members      — medical_conditions TEXT, allergies TEXT
  4. fn_get_ai_conversation     — messages TEXT
  5. fn_get_medication_schedules — times TEXT
                                  (body also casts times::JSONB for array ops)
  6. fn_search_medicines        — brand_names TEXT

Revision ID: 010
Revises: 009
Create Date: 2026-03-29
"""

from alembic import op
import sqlalchemy as sa

revision = "010"
down_revision = "009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── 1. fn_get_user_by_identifier ─────────────────────────────────────────
    op.execute(sa.text(
        "DROP FUNCTION IF EXISTS fn_get_user_by_identifier(character varying)"
    ))
    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION public.fn_get_user_by_identifier(p_identifier CHARACTER VARYING)
RETURNS TABLE (
    id                INTEGER,
    name              CHARACTER VARYING,
    email             CHARACTER VARYING,
    phone             CHARACTER VARYING,
    age               INTEGER,
    gender            CHARACTER VARYING,
    blood_group       CHARACTER VARYING,
    health_conditions TEXT,
    allergies         TEXT,
    is_active         BOOLEAN,
    is_verified       BOOLEAN,
    created_at        TIMESTAMPTZ,
    updated_at        TIMESTAMPTZ
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
        SELECT
            u.id, u.name, u.email, u.phone, u.age::INTEGER,
            u.gender, u.blood_group,
            u.health_conditions, u.allergies,
            u.is_active, u.is_verified, u.created_at, u.updated_at
        FROM users u
        WHERE (u.email = p_identifier OR u.phone = p_identifier)
          AND u.is_active = TRUE
        LIMIT 1;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES ('fn_get_user_by_identifier', SQLERRM, SQLSTATE,
            jsonb_build_object('identifier', LEFT(p_identifier, 4) || '***'));
    RAISE;
END;
$$
"""))

    # ── 2. fn_get_user_by_id ─────────────────────────────────────────────────
    op.execute(sa.text(
        "DROP FUNCTION IF EXISTS fn_get_user_by_id(integer)"
    ))
    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION public.fn_get_user_by_id(p_user_id INTEGER)
RETURNS TABLE (
    id                INTEGER,
    name              CHARACTER VARYING,
    email             CHARACTER VARYING,
    phone             CHARACTER VARYING,
    age               INTEGER,
    gender            CHARACTER VARYING,
    blood_group       CHARACTER VARYING,
    health_conditions TEXT,
    allergies         TEXT,
    is_active         BOOLEAN,
    is_verified       BOOLEAN,
    created_at        TIMESTAMPTZ,
    updated_at        TIMESTAMPTZ
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
        SELECT
            u.id, u.name, u.email, u.phone, u.age::INTEGER,
            u.gender, u.blood_group,
            u.health_conditions, u.allergies,
            u.is_active, u.is_verified, u.created_at, u.updated_at
        FROM users u
        WHERE u.id = p_user_id
          AND u.is_active = TRUE;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES ('fn_get_user_by_id', SQLERRM, SQLSTATE,
            jsonb_build_object('user_id', p_user_id));
    RAISE;
END;
$$
"""))

    # ── 3. fn_get_family_members ─────────────────────────────────────────────
    op.execute(sa.text(
        "DROP FUNCTION IF EXISTS fn_get_family_members(integer)"
    ))
    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION public.fn_get_family_members(p_user_id INTEGER)
RETURNS TABLE (
    id                 INTEGER,
    user_id            INTEGER,
    name               CHARACTER VARYING,
    relationship       CHARACTER VARYING,
    age                INTEGER,
    gender             CHARACTER VARYING,
    blood_group        CHARACTER VARYING,
    medical_conditions TEXT,
    allergies          TEXT,
    notes              TEXT,
    profile_image_url  TEXT,
    is_active          BOOLEAN,
    created_at         TIMESTAMPTZ,
    updated_at         TIMESTAMPTZ
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
        SELECT
            fm.id, fm.user_id, fm.name, fm.relationship, fm.age::INTEGER,
            fm.gender, fm.blood_group,
            fm.medical_conditions, fm.allergies,
            fm.notes, NULL::TEXT AS profile_image_url,
            fm.is_active, fm.created_at, fm.updated_at
        FROM family_members fm
        WHERE fm.user_id  = p_user_id
          AND fm.is_active = TRUE
        ORDER BY fm.created_at;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES ('fn_get_family_members', SQLERRM, SQLSTATE,
            jsonb_build_object('user_id', p_user_id));
    RAISE;
END;
$$
"""))

    # ── 4. fn_get_ai_conversation ────────────────────────────────────────────
    op.execute(sa.text(
        "DROP FUNCTION IF EXISTS fn_get_ai_conversation(integer, integer)"
    ))
    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION public.fn_get_ai_conversation(p_conversation_id INTEGER, p_user_id INTEGER)
RETURNS TABLE (
    id           INTEGER,
    user_id      INTEGER,
    title        CHARACTER VARYING,
    context_type CHARACTER VARYING,
    messages     TEXT,
    token_count  INTEGER,
    created_at   TIMESTAMPTZ,
    updated_at   TIMESTAMPTZ
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
        SELECT
            ac.id, ac.user_id, ac.title, ac.context_type,
            ac.messages, ac.token_count, ac.created_at, ac.updated_at
        FROM ai_conversations ac
        WHERE ac.id      = p_conversation_id
          AND ac.user_id = p_user_id;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES ('fn_get_ai_conversation', SQLERRM, SQLSTATE,
            jsonb_build_object('conversation_id', p_conversation_id, 'user_id', p_user_id));
    RAISE;
END;
$$
"""))

    # ── 5. fn_get_medication_schedules ───────────────────────────────────────
    #    times column is TEXT — cast to ::JSONB for array operations in body.
    op.execute(sa.text(
        "DROP FUNCTION IF EXISTS fn_get_medication_schedules(integer)"
    ))
    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION public.fn_get_medication_schedules(p_user_id INTEGER)
RETURNS TABLE (
    id                 INTEGER,
    user_id            INTEGER,
    family_member_id   INTEGER,
    prescription_id    INTEGER,
    medicine_name      CHARACTER VARYING,
    dosage             CHARACTER VARYING,
    frequency          CHARACTER VARYING,
    times              TEXT,
    instructions       TEXT,
    start_date         DATE,
    end_date           DATE,
    refill_date        DATE,
    total_quantity     INTEGER,
    remaining_quantity INTEGER,
    is_active          BOOLEAN,
    created_at         TIMESTAMPTZ,
    updated_at         TIMESTAMPTZ,
    next_reminder_time TIMESTAMPTZ
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
        SELECT
            ms.id, ms.user_id, ms.family_member_id, ms.prescription_id,
            ms.medicine_name, ms.dosage, ms.frequency,
            ms.times,
            ms.instructions, ms.start_date, ms.end_date, ms.refill_date,
            ms.total_quantity, ms.remaining_quantity,
            ms.is_active, ms.created_at, ms.updated_at,
            CASE
                WHEN ms.times IS NOT NULL
                     AND jsonb_array_length(ms.times::JSONB) > 0
                THEN (NOW()::DATE + (ms.times::JSONB->>0)::TIME)::TIMESTAMPTZ
                ELSE NULL
            END AS next_reminder_time
        FROM medication_schedules ms
        WHERE ms.user_id   = p_user_id
          AND ms.is_active = TRUE
        ORDER BY ms.created_at DESC;
EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES ('fn_get_medication_schedules', SQLERRM, SQLSTATE,
            jsonb_build_object('user_id', p_user_id));
    RAISE;
END;
$$
"""))

    # ── 6. fn_search_medicines ───────────────────────────────────────────────
    op.execute(sa.text(
        "DROP FUNCTION IF EXISTS fn_search_medicines(text, integer, integer)"
    ))
    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION public.fn_search_medicines(
    p_query  TEXT,
    p_limit  INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    id             INTEGER,
    name           CHARACTER VARYING,
    generic_name   CHARACTER VARYING,
    brand_names    TEXT,
    drug_class     CHARACTER VARYING,
    schedule       CHARACTER VARYING,
    schedule_label TEXT,
    tga_registered BOOLEAN,
    rank           REAL
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    _tsquery TSQUERY;
BEGIN
    _tsquery := websearch_to_tsquery('english', p_query);
    RETURN QUERY
    SELECT
        m.id, m.name, m.generic_name, m.brand_names, m.drug_class, m.schedule,
        CASE m.schedule
            WHEN 'S2' THEN 'Pharmacy Only'
            WHEN 'S3' THEN 'Pharmacist Only'
            WHEN 'S4' THEN 'Prescription Only'
            WHEN 'S8' THEN 'Controlled Drug'
            WHEN 'S9' THEN 'Prohibited Substance'
            ELSE 'Unscheduled (OTC)'
        END,
        m.tga_registered,
        (ts_rank(m.search_vector, _tsquery) * 0.7
         + similarity(m.name, p_query) * 0.3)::REAL AS rank
    FROM medicines m
    WHERE m.search_vector @@ _tsquery
       OR m.name ILIKE '%' || p_query || '%'
       OR m.generic_name ILIKE '%' || p_query || '%'
    ORDER BY rank DESC, m.tga_registered DESC, m.name ASC
    LIMIT p_limit OFFSET p_offset;
END;
$$
"""))


def downgrade() -> None:
    # Restore the (broken) JSONB versions for rollback symmetry.
    # These are intentionally left as stubs — reverting would re-introduce
    # the DatatypeMismatchError and is not recommended.
    pass
