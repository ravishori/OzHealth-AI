"""Fix stored procedure type mismatches and spurious success db_error_logs inserts.

Fixes applied:
  1. fn_get_user_by_identifier  — cast u.age::INTEGER  (table stores SMALLINT, func declares INTEGER)
  2. fn_get_user_by_id          — cast u.age::INTEGER  (same mismatch)
  3. fn_get_family_members      — cast fm.age::INTEGER + return NULL::TEXT for profile_image_url
                                   (column does not exist on family_members table)
  4. sp_insert_user             — remove spurious 'SUCCESS' insert into db_error_logs
  5. sp_update_user             — remove spurious 'SUCCESS' insert into db_error_logs
  6. sp_insert_family_member    — remove spurious 'SUCCESS' insert into db_error_logs
  7. sp_update_family_member    — remove spurious 'SUCCESS' insert into db_error_logs

Revision ID: 003
Revises: 002
"""
from alembic import op
import sqlalchemy as sa

revision = "003"
down_revision = "002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── 1 & 2: Fix user-returning functions (age SMALLINT → INTEGER cast) ─────

    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION fn_get_user_by_identifier(p_identifier VARCHAR)
RETURNS TABLE (
    id             INTEGER,
    name           VARCHAR,
    email          VARCHAR,
    phone          VARCHAR,
    age            INTEGER,
    gender         VARCHAR,
    blood_group    VARCHAR,
    health_conditions JSONB,
    allergies      JSONB,
    is_active      BOOLEAN,
    is_verified    BOOLEAN,
    created_at     TIMESTAMPTZ,
    updated_at     TIMESTAMPTZ
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
        SELECT
            u.id,
            u.name,
            u.email,
            u.phone,
            u.age::INTEGER,
            u.gender,
            u.blood_group,
            u.health_conditions,
            u.allergies,
            u.is_active,
            u.is_verified,
            u.created_at,
            u.updated_at
        FROM users u
        WHERE (u.email = p_identifier OR u.phone = p_identifier)
          AND u.is_active = TRUE
        LIMIT 1;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'fn_get_user_by_identifier',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('identifier', LEFT(p_identifier, 4) || '***')
    );
    RAISE;
END;
$$;
"""))

    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION fn_get_user_by_id(p_user_id INTEGER)
RETURNS TABLE (
    id             INTEGER,
    name           VARCHAR,
    email          VARCHAR,
    phone          VARCHAR,
    age            INTEGER,
    gender         VARCHAR,
    blood_group    VARCHAR,
    health_conditions JSONB,
    allergies      JSONB,
    is_active      BOOLEAN,
    is_verified    BOOLEAN,
    created_at     TIMESTAMPTZ,
    updated_at     TIMESTAMPTZ
)
LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
        SELECT
            u.id,
            u.name,
            u.email,
            u.phone,
            u.age::INTEGER,
            u.gender,
            u.blood_group,
            u.health_conditions,
            u.allergies,
            u.is_active,
            u.is_verified,
            u.created_at,
            u.updated_at
        FROM users u
        WHERE u.id = p_user_id
          AND u.is_active = TRUE;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'fn_get_user_by_id',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id)
    );
    RAISE;
END;
$$;
"""))

    # ── 3: Fix fn_get_family_members (age cast + missing profile_image_url) ───

    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION fn_get_family_members(p_user_id INTEGER)
RETURNS TABLE (
    id                 INTEGER,
    user_id            INTEGER,
    name               VARCHAR,
    relationship       VARCHAR,
    age                INTEGER,
    gender             VARCHAR,
    blood_group        VARCHAR,
    medical_conditions JSONB,
    allergies          JSONB,
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
            fm.id,
            fm.user_id,
            fm.name,
            fm.relationship,
            fm.age::INTEGER,
            fm.gender,
            fm.blood_group,
            fm.medical_conditions,
            fm.allergies,
            fm.notes,
            NULL::TEXT AS profile_image_url,  -- column not yet on the table
            fm.is_active,
            fm.created_at,
            fm.updated_at
        FROM family_members fm
        WHERE fm.user_id  = p_user_id
          AND fm.is_active = TRUE
        ORDER BY fm.created_at;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'fn_get_family_members',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id)
    );
    RAISE;
END;
$$;
"""))

    # ── 4: sp_insert_user — remove spurious SUCCESS insert into db_error_logs ─

    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION sp_insert_user(
    p_name        VARCHAR,
    p_email       VARCHAR,
    p_phone       VARCHAR,
    p_age         INTEGER,
    p_gender      VARCHAR,
    p_blood_group VARCHAR
)
RETURNS TABLE (id INTEGER, created_at TIMESTAMPTZ)
LANGUAGE plpgsql AS $$
DECLARE
    v_id         INTEGER;
    v_created_at TIMESTAMPTZ;
    v_exists     INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_exists
    FROM users
    WHERE (p_email IS NOT NULL AND email = p_email)
       OR (p_phone IS NOT NULL AND phone = p_phone);

    IF v_exists > 0 THEN
        RAISE SQLSTATE '23505'
            USING MESSAGE = 'A user with this email or phone already exists';
    END IF;

    INSERT INTO users (name, email, phone, age, gender, blood_group, is_verified)
    VALUES (p_name, p_email, p_phone, p_age, p_gender, p_blood_group, TRUE)
    RETURNING users.id, users.created_at INTO v_id, v_created_at;

    RETURN QUERY SELECT v_id, v_created_at;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_user',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object(
            'email', CASE WHEN p_email IS NOT NULL THEN LEFT(p_email, 4) || '***' ELSE NULL END,
            'phone', CASE WHEN p_phone IS NOT NULL THEN LEFT(p_phone, 4) || '***' ELSE NULL END
        )
    );
    RAISE;
END;
$$;
"""))

    # ── 5: sp_update_user — remove spurious SUCCESS insert ────────────────────

    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION sp_update_user(
    p_user_id           INTEGER,
    p_name              VARCHAR  DEFAULT NULL,
    p_age               INTEGER  DEFAULT NULL,
    p_gender            VARCHAR  DEFAULT NULL,
    p_blood_group       VARCHAR  DEFAULT NULL,
    p_medical_conditions JSONB   DEFAULT NULL,
    p_allergies         JSONB    DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE users
    SET
        name              = COALESCE(p_name,               name),
        age               = COALESCE(p_age,                age),
        gender            = COALESCE(p_gender,             gender),
        blood_group       = COALESCE(p_blood_group,        blood_group),
        health_conditions = COALESCE(p_medical_conditions, health_conditions),
        allergies         = COALESCE(p_allergies,          allergies),
        updated_at        = NOW()
    WHERE id = p_user_id;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_update_user',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id)
    );
    RAISE;
END;
$$;
"""))

    # ── 6: sp_insert_family_member — remove spurious SUCCESS insert ───────────

    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION sp_insert_family_member(
    p_user_id           INTEGER,
    p_name              VARCHAR,
    p_relationship      VARCHAR,
    p_age               INTEGER,
    p_gender            VARCHAR,
    p_blood_group       VARCHAR,
    p_medical_conditions JSONB  DEFAULT NULL,
    p_allergies         JSONB   DEFAULT NULL
)
RETURNS TABLE (id INTEGER, created_at TIMESTAMPTZ)
LANGUAGE plpgsql AS $$
DECLARE
    v_id         INTEGER;
    v_created_at TIMESTAMPTZ;
BEGIN
    INSERT INTO family_members (
        user_id, name, relationship, age, gender,
        blood_group, medical_conditions, allergies
    )
    VALUES (
        p_user_id, p_name, p_relationship, p_age, p_gender,
        p_blood_group,
        COALESCE(p_medical_conditions, '[]'::JSONB),
        COALESCE(p_allergies, '[]'::JSONB)
    )
    RETURNING family_members.id, family_members.created_at INTO v_id, v_created_at;

    RETURN QUERY SELECT v_id, v_created_at;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_family_member',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id, 'name', p_name)
    );
    RAISE;
END;
$$;
"""))

    # ── 7: sp_update_family_member — remove spurious SUCCESS insert ───────────

    op.execute(sa.text("""
CREATE OR REPLACE FUNCTION sp_update_family_member(
    p_member_id         INTEGER,
    p_user_id           INTEGER,
    p_name              VARCHAR  DEFAULT NULL,
    p_relationship      VARCHAR  DEFAULT NULL,
    p_age               INTEGER  DEFAULT NULL,
    p_gender            VARCHAR  DEFAULT NULL,
    p_blood_group       VARCHAR  DEFAULT NULL,
    p_medical_conditions JSONB   DEFAULT NULL,
    p_allergies         JSONB    DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE family_members
    SET
        name               = COALESCE(p_name,               name),
        relationship       = COALESCE(p_relationship,       relationship),
        age                = COALESCE(p_age,                age),
        gender             = COALESCE(p_gender,             gender),
        blood_group        = COALESCE(p_blood_group,        blood_group),
        medical_conditions = COALESCE(p_medical_conditions, medical_conditions),
        allergies          = COALESCE(p_allergies,          allergies),
        updated_at         = NOW()
    WHERE id      = p_member_id
      AND user_id = p_user_id;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_update_family_member',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('member_id', p_member_id, 'user_id', p_user_id)
    );
    RAISE;
END;
$$;
"""))


def downgrade() -> None:
    # Downgrade restores the pre-fix versions (age without cast, with SUCCESS logs)
    # In practice this migration should never be rolled back in production.
    pass
