"""OTP hybrid model + stored procedures for all domain operations

Revision ID: 002
Revises: 001
Create Date: 2026-03-23 00:00:00.000000

Changes:
  - ALTER otps.otp_code  VARCHAR(10) → VARCHAR(6)  (plain 6-digit OTP)
  - ADD   otps.otp_hash  VARCHAR(64) NOT NULL DEFAULT ''  (HMAC-SHA256 hex)
  - CREATE TABLE db_error_logs  (internal procedure error logging)
  - CREATE 25 stored procedures / functions covering all domain operations
"""

from alembic import op
import sqlalchemy as sa

revision = '002'
down_revision = '001'
branch_labels = None
depends_on = None


# ---------------------------------------------------------------------------
# Helper — execute raw SQL as a text block
# ---------------------------------------------------------------------------
def _sql(stmt: str) -> None:
    op.execute(sa.text(stmt))


# ===========================================================================
# UPGRADE
# ===========================================================================

def upgrade() -> None:
    # ── A) Alter otps table ────────────────────────────────────────────────
    _sql("ALTER TABLE otps ALTER COLUMN otp_code TYPE VARCHAR(6)")
    _sql("""
        ALTER TABLE otps
        ADD COLUMN IF NOT EXISTS otp_hash VARCHAR(64) NOT NULL DEFAULT ''
    """)

    # ── B) db_error_logs ──────────────────────────────────────────────────
    _sql("""
        CREATE TABLE IF NOT EXISTS db_error_logs (
            id            SERIAL PRIMARY KEY,
            proc_name     VARCHAR(100),
            error_message TEXT,
            error_state   VARCHAR(10),
            input_params  JSONB,
            created_at    TIMESTAMPTZ DEFAULT NOW()
        )
    """)

    # ── C) Stored procedures / functions ──────────────────────────────────
    # Drop all functions first so PostgreSQL can accept any return-type change.
    # Using CASCADE covers any views/rules that might depend on them.
    _sql("""
        DROP FUNCTION IF EXISTS sp_insert_otp(VARCHAR,VARCHAR,VARCHAR,VARCHAR,TIMESTAMPTZ) CASCADE;
        DROP FUNCTION IF EXISTS fn_get_valid_otps(VARCHAR,VARCHAR)                        CASCADE;
        DROP FUNCTION IF EXISTS sp_mark_otp_used(INTEGER)                                 CASCADE;
        DROP FUNCTION IF EXISTS sp_expire_old_otps()                                      CASCADE;
        DROP FUNCTION IF EXISTS fn_get_user_by_identifier(VARCHAR)                        CASCADE;
        DROP FUNCTION IF EXISTS fn_get_user_by_id(INTEGER)                                CASCADE;
        DROP FUNCTION IF EXISTS sp_insert_user(VARCHAR,VARCHAR,VARCHAR,INTEGER,VARCHAR,VARCHAR) CASCADE;
        DROP FUNCTION IF EXISTS sp_update_user(INTEGER,VARCHAR,INTEGER,VARCHAR,VARCHAR,TEXT,VARCHAR,JSONB,JSONB,JSONB) CASCADE;
        DROP FUNCTION IF EXISTS sp_insert_family_member(INTEGER,VARCHAR,VARCHAR,INTEGER,VARCHAR,VARCHAR,JSONB,JSONB,TEXT) CASCADE;
        DROP FUNCTION IF EXISTS fn_get_family_members(INTEGER)                            CASCADE;
        DROP FUNCTION IF EXISTS sp_update_family_member(INTEGER,INTEGER,VARCHAR,VARCHAR,INTEGER,VARCHAR,VARCHAR,JSONB,JSONB,TEXT) CASCADE;
        DROP FUNCTION IF EXISTS sp_delete_family_member(INTEGER,INTEGER)                  CASCADE;
        DROP FUNCTION IF EXISTS sp_insert_health_metric(INTEGER,INTEGER,VARCHAR,NUMERIC,NUMERIC,VARCHAR,TEXT,TIMESTAMPTZ) CASCADE;
        DROP FUNCTION IF EXISTS fn_get_health_summary(INTEGER)                            CASCADE;
        DROP FUNCTION IF EXISTS sp_insert_emergency_contact(INTEGER,VARCHAR,VARCHAR,VARCHAR,BOOLEAN) CASCADE;
        DROP FUNCTION IF EXISTS fn_get_emergency_contacts(INTEGER)                        CASCADE;
        DROP FUNCTION IF EXISTS sp_insert_medical_record(INTEGER,INTEGER,VARCHAR,VARCHAR,TEXT,VARCHAR,INTEGER,VARCHAR,TEXT,DATE) CASCADE;
        DROP FUNCTION IF EXISTS fn_get_medical_records(INTEGER,INTEGER)                   CASCADE;
        DROP FUNCTION IF EXISTS sp_insert_medication_schedule(INTEGER,INTEGER,INTEGER,VARCHAR,VARCHAR,VARCHAR,JSONB,TEXT,DATE,DATE,DATE,INTEGER,INTEGER) CASCADE;
        DROP FUNCTION IF EXISTS fn_get_medication_schedules(INTEGER)                      CASCADE;
        DROP FUNCTION IF EXISTS sp_update_medication_schedule(INTEGER,INTEGER,VARCHAR,VARCHAR,VARCHAR,JSONB,TEXT,DATE,DATE,DATE,INTEGER,INTEGER,BOOLEAN) CASCADE;
        DROP FUNCTION IF EXISTS sp_delete_medication_schedule(INTEGER,INTEGER)            CASCADE;
        DROP FUNCTION IF EXISTS sp_upsert_ai_conversation(INTEGER,VARCHAR,VARCHAR,JSONB,INTEGER) CASCADE;
        DROP FUNCTION IF EXISTS fn_get_ai_conversation(INTEGER,VARCHAR)                   CASCADE;
        DROP FUNCTION IF EXISTS fn_user_stats()                                           CASCADE;
    """)

    # ── 1. sp_insert_otp ──────────────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_insert_otp(
    p_identifier  VARCHAR,
    p_otp_code    VARCHAR,
    p_otp_hash    VARCHAR,
    p_purpose     VARCHAR,
    p_expires_at  TIMESTAMPTZ
)
RETURNS TABLE(id INTEGER, created_at TIMESTAMPTZ) AS $$
DECLARE
    v_id         INTEGER;
    v_created_at TIMESTAMPTZ;
BEGIN
    INSERT INTO otps (identifier, otp_code, otp_hash, purpose, is_used, expires_at)
    VALUES (p_identifier, p_otp_code, p_otp_hash, p_purpose, FALSE, p_expires_at)
    RETURNING otps.id, otps.created_at INTO v_id, v_created_at;

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_otp',
        'SUCCESS',
        '00000',
        jsonb_build_object(
            'identifier', LEFT(p_identifier, 4) || '***',
            'purpose',     p_purpose,
            'expires_at',  p_expires_at
        )
    );

    RETURN QUERY SELECT v_id, v_created_at;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_otp',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object(
            'identifier', LEFT(p_identifier, 4) || '***',
            'purpose',     p_purpose,
            'expires_at',  p_expires_at
        )
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 2. fn_get_valid_otps ──────────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION fn_get_valid_otps(
    p_identifier VARCHAR,
    p_purpose    VARCHAR
)
RETURNS TABLE(
    id         INTEGER,
    otp_code   VARCHAR,
    otp_hash   VARCHAR,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
        SELECT
            o.id,
            o.otp_code,
            o.otp_hash,
            o.created_at
        FROM otps o
        WHERE o.identifier = p_identifier
          AND o.purpose    = p_purpose
          AND o.is_used    = FALSE
          AND o.expires_at > NOW()
        ORDER BY o.created_at DESC;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'fn_get_valid_otps',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object(
            'identifier', LEFT(p_identifier, 4) || '***',
            'purpose',     p_purpose
        )
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 3. sp_mark_otp_used ───────────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_mark_otp_used(p_otp_id INTEGER)
RETURNS VOID AS $$
BEGIN
    UPDATE otps SET is_used = TRUE WHERE id = p_otp_id;

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_mark_otp_used',
        'SUCCESS',
        '00000',
        jsonb_build_object('otp_id', p_otp_id)
    );

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_mark_otp_used',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('otp_id', p_otp_id)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 4. sp_expire_old_otps ─────────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_expire_old_otps()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    DELETE FROM otps
    WHERE expires_at < NOW()
       OR (is_used = TRUE AND created_at < NOW() - INTERVAL '7 days');

    GET DIAGNOSTICS v_count = ROW_COUNT;

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_expire_old_otps',
        'SUCCESS — deleted ' || v_count || ' rows',
        '00000',
        jsonb_build_object('deleted_count', v_count)
    );

    RETURN v_count;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_expire_old_otps',
        SQLERRM,
        SQLSTATE,
        '{}'::JSONB
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 5. fn_get_user_by_identifier ──────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION fn_get_user_by_identifier(p_identifier VARCHAR)
RETURNS TABLE(
    id               INTEGER,
    name             VARCHAR,
    email            VARCHAR,
    phone            VARCHAR,
    age              INTEGER,
    gender           VARCHAR,
    blood_group      VARCHAR,
    health_conditions JSONB,
    allergies        JSONB,
    is_active        BOOLEAN,
    is_verified      BOOLEAN,
    created_at       TIMESTAMPTZ,
    updated_at       TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
        SELECT
            u.id,
            u.name,
            u.email,
            u.phone,
            u.age,
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
$$ LANGUAGE plpgsql;
""")

    # ── 6. fn_get_user_by_id ──────────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION fn_get_user_by_id(p_user_id INTEGER)
RETURNS TABLE(
    id               INTEGER,
    name             VARCHAR,
    email            VARCHAR,
    phone            VARCHAR,
    age              INTEGER,
    gender           VARCHAR,
    blood_group      VARCHAR,
    health_conditions JSONB,
    allergies        JSONB,
    is_active        BOOLEAN,
    is_verified      BOOLEAN,
    created_at       TIMESTAMPTZ,
    updated_at       TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
        SELECT
            u.id,
            u.name,
            u.email,
            u.phone,
            u.age,
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
$$ LANGUAGE plpgsql;
""")

    # ── 7. sp_insert_user ─────────────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_insert_user(
    p_name        VARCHAR,
    p_email       VARCHAR,
    p_phone       VARCHAR,
    p_age         INTEGER,
    p_gender      VARCHAR,
    p_blood_group VARCHAR
)
RETURNS TABLE(id INTEGER, created_at TIMESTAMPTZ) AS $$
DECLARE
    v_id         INTEGER;
    v_created_at TIMESTAMPTZ;
    v_exists     INTEGER;
BEGIN
    -- Duplicate check
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

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_user',
        'SUCCESS',
        '00000',
        jsonb_build_object(
            'email', CASE WHEN p_email IS NOT NULL THEN LEFT(p_email, 4) || '***' ELSE NULL END,
            'phone', CASE WHEN p_phone IS NOT NULL THEN LEFT(p_phone, 4) || '***' ELSE NULL END,
            'name',  p_name
        )
    );

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
$$ LANGUAGE plpgsql;
""")

    # ── 8. sp_update_user ─────────────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_update_user(
    p_user_id           INTEGER,
    p_name              VARCHAR,
    p_age               INTEGER,
    p_gender            VARCHAR,
    p_blood_group       VARCHAR,
    p_medical_conditions JSONB,
    p_allergies         JSONB
)
RETURNS VOID AS $$
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

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_update_user',
        'SUCCESS',
        '00000',
        jsonb_build_object('user_id', p_user_id)
    );

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
$$ LANGUAGE plpgsql;
""")

    # ── 9. sp_insert_family_member ────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_insert_family_member(
    p_user_id            INTEGER,
    p_name               VARCHAR,
    p_relationship       VARCHAR,
    p_age                INTEGER,
    p_gender             VARCHAR,
    p_blood_group        VARCHAR,
    p_medical_conditions JSONB,
    p_allergies          JSONB
)
RETURNS TABLE(id INTEGER, created_at TIMESTAMPTZ) AS $$
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

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_family_member',
        'SUCCESS',
        '00000',
        jsonb_build_object('user_id', p_user_id, 'name', p_name)
    );

    RETURN QUERY SELECT v_id, v_created_at;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_family_member',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 10. fn_get_family_members ─────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION fn_get_family_members(p_user_id INTEGER)
RETURNS TABLE(
    id                   INTEGER,
    user_id              INTEGER,
    name                 VARCHAR,
    relationship         VARCHAR,
    age                  INTEGER,
    gender               VARCHAR,
    blood_group          VARCHAR,
    medical_conditions   JSONB,
    allergies            JSONB,
    notes                TEXT,
    profile_image_url    TEXT,
    is_active            BOOLEAN,
    created_at           TIMESTAMPTZ,
    updated_at           TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
        SELECT
            fm.id,
            fm.user_id,
            fm.name,
            fm.relationship,
            fm.age,
            fm.gender,
            fm.blood_group,
            fm.medical_conditions,
            fm.allergies,
            fm.notes,
            fm.profile_image_url,
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
$$ LANGUAGE plpgsql;
""")

    # ── 11. sp_update_family_member ───────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_update_family_member(
    p_member_id          INTEGER,
    p_user_id            INTEGER,
    p_name               VARCHAR,
    p_relationship       VARCHAR,
    p_age                INTEGER,
    p_gender             VARCHAR,
    p_blood_group        VARCHAR,
    p_medical_conditions JSONB,
    p_allergies          JSONB
)
RETURNS VOID AS $$
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
      AND user_id = p_user_id;   -- security: only owner can update

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_update_family_member',
        'SUCCESS',
        '00000',
        jsonb_build_object('member_id', p_member_id, 'user_id', p_user_id)
    );

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
$$ LANGUAGE plpgsql;
""")

    # ── 12. sp_delete_family_member ───────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_delete_family_member(
    p_member_id INTEGER,
    p_user_id   INTEGER
)
RETURNS VOID AS $$
BEGIN
    UPDATE family_members
    SET is_active = FALSE
    WHERE id      = p_member_id
      AND user_id = p_user_id;

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_delete_family_member',
        'SUCCESS',
        '00000',
        jsonb_build_object('member_id', p_member_id, 'user_id', p_user_id)
    );

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_delete_family_member',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('member_id', p_member_id, 'user_id', p_user_id)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 13. sp_insert_health_metric ───────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_insert_health_metric(
    p_user_id          INTEGER,
    p_family_member_id INTEGER,
    p_metric_type      VARCHAR,
    p_value            NUMERIC,
    p_value2           NUMERIC,
    p_unit             VARCHAR,
    p_notes            TEXT
)
RETURNS TABLE(id INTEGER, recorded_at TIMESTAMPTZ) AS $$
DECLARE
    v_id          INTEGER;
    v_recorded_at TIMESTAMPTZ;
BEGIN
    INSERT INTO health_metrics (
        user_id, family_member_id, metric_type,
        value, value2, unit, notes
    )
    VALUES (
        p_user_id, p_family_member_id, p_metric_type,
        p_value, p_value2, p_unit, p_notes
    )
    RETURNING health_metrics.id, health_metrics.recorded_at INTO v_id, v_recorded_at;

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_health_metric',
        'SUCCESS',
        '00000',
        jsonb_build_object(
            'user_id',     p_user_id,
            'metric_type', p_metric_type
        )
    );

    RETURN QUERY SELECT v_id, v_recorded_at;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_health_metric',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id, 'metric_type', p_metric_type)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 14. fn_get_health_summary ─────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION fn_get_health_summary(p_user_id INTEGER)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB := '{}'::JSONB;
    v_metric RECORD;
    v_trend  VARCHAR(10);
    v_status VARCHAR(20);
    v_latest NUMERIC;
    v_prev   NUMERIC;
    v_latest2 NUMERIC;
BEGIN
    FOR v_metric IN
        SELECT DISTINCT metric_type FROM health_metrics WHERE user_id = p_user_id
    LOOP
        -- Get last 5 readings for this metric type
        WITH ranked AS (
            SELECT
                value,
                value2,
                unit,
                recorded_at,
                ROW_NUMBER() OVER (ORDER BY recorded_at DESC) AS rn
            FROM health_metrics
            WHERE user_id    = p_user_id
              AND metric_type = v_metric.metric_type
        ),
        last_two AS (
            SELECT
                MAX(CASE WHEN rn = 1 THEN value   END) AS latest_val,
                MAX(CASE WHEN rn = 1 THEN value2  END) AS latest_val2,
                MAX(CASE WHEN rn = 1 THEN unit    END) AS latest_unit,
                MAX(CASE WHEN rn = 1 THEN recorded_at END) AS latest_ts,
                MAX(CASE WHEN rn = 2 THEN value   END) AS prev_val
            FROM ranked WHERE rn <= 2
        ),
        recent AS (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'value',       value,
                    'value2',      value2,
                    'unit',        unit,
                    'recorded_at', recorded_at
                ) ORDER BY recorded_at DESC
            ) AS readings
            FROM ranked WHERE rn <= 5
        )
        SELECT
            lt.latest_val,
            lt.latest_val2,
            lt.latest_unit,
            lt.latest_ts,
            lt.prev_val,
            r.readings
        INTO v_latest, v_latest2, v_status, v_trend, v_prev, v_trend
        FROM last_two lt, recent r;

        -- Recompute properly from the CTEs
        SELECT
            lt.latest_val,
            lt.latest_val2,
            lt.latest_unit,
            lt.latest_ts,
            lt.prev_val,
            r.readings
        INTO
            v_latest, v_latest2, v_status, v_trend, v_prev, v_trend
        FROM (
            SELECT
                MAX(CASE WHEN rn=1 THEN value  END) AS latest_val,
                MAX(CASE WHEN rn=1 THEN value2 END) AS latest_val2,
                MAX(CASE WHEN rn=1 THEN unit   END) AS latest_unit,
                MAX(CASE WHEN rn=1 THEN recorded_at::TEXT END) AS latest_ts,
                MAX(CASE WHEN rn=2 THEN value  END) AS prev_val
            FROM (
                SELECT value, value2, unit, recorded_at,
                       ROW_NUMBER() OVER (ORDER BY recorded_at DESC) AS rn
                FROM health_metrics
                WHERE user_id = p_user_id AND metric_type = v_metric.metric_type
            ) sub WHERE rn <= 2
        ) lt,
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'value',       value,
                    'value2',      value2,
                    'unit',        unit,
                    'recorded_at', recorded_at
                ) ORDER BY recorded_at DESC
            ) AS readings
            FROM (
                SELECT value, value2, unit, recorded_at,
                       ROW_NUMBER() OVER (ORDER BY recorded_at DESC) AS rn
                FROM health_metrics
                WHERE user_id = p_user_id AND metric_type = v_metric.metric_type
            ) sub WHERE rn <= 5
        ) r;

        -- Trend
        IF v_prev IS NULL THEN
            v_trend := 'stable';
        ELSIF v_latest > v_prev THEN
            v_trend := 'up';
        ELSIF v_latest < v_prev THEN
            v_trend := 'down';
        ELSE
            v_trend := 'stable';
        END IF;

        -- Status based on metric type ranges
        v_status := CASE v_metric.metric_type
            WHEN 'blood_sugar' THEN
                CASE
                    WHEN v_latest < 70   THEN 'low'
                    WHEN v_latest <= 99  THEN 'normal'
                    WHEN v_latest <= 125 THEN 'elevated'
                    ELSE 'high'
                END
            WHEN 'heart_rate' THEN
                CASE
                    WHEN v_latest < 60   THEN 'low'
                    WHEN v_latest <= 100 THEN 'normal'
                    ELSE 'high'
                END
            WHEN 'oxygen_saturation' THEN
                CASE
                    WHEN v_latest >= 95  THEN 'normal'
                    WHEN v_latest >= 90  THEN 'elevated'
                    ELSE 'low'
                END
            WHEN 'blood_pressure' THEN
                -- value = systolic, value2 = diastolic
                CASE
                    WHEN v_latest < 90 OR COALESCE(v_latest2, 60) < 60  THEN 'low'
                    WHEN v_latest <= 120 AND COALESCE(v_latest2, 80) <= 80 THEN 'normal'
                    WHEN v_latest <= 139 OR COALESCE(v_latest2, 89) <= 89 THEN 'elevated'
                    ELSE 'high'
                END
            WHEN 'weight' THEN 'normal'   -- BMI context needed; default to normal
            ELSE 'normal'
        END;

        v_result := v_result || jsonb_build_object(
            v_metric.metric_type,
            jsonb_build_object(
                'latest_value',  v_latest,
                'latest_value2', v_latest2,
                'trend',         v_trend,
                'status',        v_status
            )
        );
    END LOOP;

    RETURN v_result;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'fn_get_health_summary',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 15. sp_insert_emergency_contact ───────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_insert_emergency_contact(
    p_user_id      INTEGER,
    p_name         VARCHAR,
    p_phone        VARCHAR,
    p_relationship VARCHAR
)
RETURNS TABLE(id INTEGER, created_at TIMESTAMPTZ) AS $$
DECLARE
    v_id         INTEGER;
    v_created_at TIMESTAMPTZ;
BEGIN
    INSERT INTO emergency_contacts (user_id, name, phone, relationship)
    VALUES (p_user_id, p_name, p_phone, p_relationship)
    RETURNING emergency_contacts.id, emergency_contacts.created_at INTO v_id, v_created_at;

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_emergency_contact',
        'SUCCESS',
        '00000',
        jsonb_build_object('user_id', p_user_id, 'name', p_name)
    );

    RETURN QUERY SELECT v_id, v_created_at;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_emergency_contact',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 16. fn_get_emergency_contacts ─────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION fn_get_emergency_contacts(p_user_id INTEGER)
RETURNS TABLE(
    id           INTEGER,
    user_id      INTEGER,
    name         VARCHAR,
    phone        VARCHAR,
    relationship VARCHAR,
    is_primary   BOOLEAN,
    created_at   TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
        SELECT
            ec.id,
            ec.user_id,
            ec.name,
            ec.phone,
            ec.relationship,
            ec.is_primary,
            ec.created_at
        FROM emergency_contacts ec
        WHERE ec.user_id = p_user_id
        ORDER BY ec.is_primary DESC, ec.created_at;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'fn_get_emergency_contacts',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 17. sp_insert_medical_record ──────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_insert_medical_record(
    p_user_id          INTEGER,
    p_family_member_id INTEGER,
    p_record_type      VARCHAR,
    p_title            VARCHAR,
    p_file_url         TEXT,
    p_file_name        VARCHAR,
    p_file_size        INTEGER,
    p_file_type        VARCHAR,
    p_notes            TEXT,
    p_record_date      DATE
)
RETURNS TABLE(id INTEGER, created_at TIMESTAMPTZ) AS $$
DECLARE
    v_id         INTEGER;
    v_created_at TIMESTAMPTZ;
BEGIN
    INSERT INTO medical_records (
        user_id, family_member_id, record_type, title,
        file_url, file_name, file_size, file_type,
        notes, record_date
    )
    VALUES (
        p_user_id, p_family_member_id, p_record_type, p_title,
        p_file_url, p_file_name, p_file_size, p_file_type,
        p_notes, p_record_date
    )
    RETURNING medical_records.id, medical_records.created_at INTO v_id, v_created_at;

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_medical_record',
        'SUCCESS',
        '00000',
        jsonb_build_object(
            'user_id',     p_user_id,
            'record_type', p_record_type
        )
    );

    RETURN QUERY SELECT v_id, v_created_at;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_medical_record',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id, 'record_type', p_record_type)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 18. fn_get_medical_records ────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION fn_get_medical_records(
    p_user_id     INTEGER,
    p_record_type VARCHAR
)
RETURNS TABLE(
    id               INTEGER,
    user_id          INTEGER,
    family_member_id INTEGER,
    record_type      VARCHAR,
    title            VARCHAR,
    file_url         TEXT,
    file_name        VARCHAR,
    file_size        INTEGER,
    file_type        VARCHAR,
    notes            TEXT,
    record_date      DATE,
    is_active        BOOLEAN,
    created_at       TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
        SELECT
            mr.id,
            mr.user_id,
            mr.family_member_id,
            mr.record_type,
            mr.title,
            mr.file_url,
            mr.file_name,
            mr.file_size,
            mr.file_type,
            mr.notes,
            mr.record_date,
            mr.is_active,
            mr.created_at
        FROM medical_records mr
        WHERE mr.user_id   = p_user_id
          AND mr.is_active = TRUE
          AND (p_record_type IS NULL OR mr.record_type = p_record_type)
        ORDER BY mr.created_at DESC;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'fn_get_medical_records',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id, 'record_type', p_record_type)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 19. sp_insert_medication_schedule ─────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_insert_medication_schedule(
    p_user_id          INTEGER,
    p_family_member_id INTEGER,
    p_medicine_name    VARCHAR,
    p_dosage           VARCHAR,
    p_frequency        VARCHAR,
    p_times            JSONB,
    p_instructions     TEXT,
    p_start_date       DATE,
    p_end_date         DATE
)
RETURNS TABLE(id INTEGER, created_at TIMESTAMPTZ) AS $$
DECLARE
    v_id         INTEGER;
    v_created_at TIMESTAMPTZ;
BEGIN
    INSERT INTO medication_schedules (
        user_id, family_member_id, medicine_name, dosage,
        frequency, times, instructions, start_date, end_date
    )
    VALUES (
        p_user_id, p_family_member_id, p_medicine_name, p_dosage,
        p_frequency,
        COALESCE(p_times, '[]'::JSONB),
        p_instructions, p_start_date, p_end_date
    )
    RETURNING medication_schedules.id, medication_schedules.created_at INTO v_id, v_created_at;

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_medication_schedule',
        'SUCCESS',
        '00000',
        jsonb_build_object(
            'user_id',       p_user_id,
            'medicine_name', p_medicine_name
        )
    );

    RETURN QUERY SELECT v_id, v_created_at;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_insert_medication_schedule',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id, 'medicine_name', p_medicine_name)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 20. fn_get_medication_schedules ───────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION fn_get_medication_schedules(p_user_id INTEGER)
RETURNS TABLE(
    id                 INTEGER,
    user_id            INTEGER,
    family_member_id   INTEGER,
    prescription_id    INTEGER,
    medicine_name      VARCHAR,
    dosage             VARCHAR,
    frequency          VARCHAR,
    times              JSONB,
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
) AS $$
BEGIN
    RETURN QUERY
        SELECT
            ms.id,
            ms.user_id,
            ms.family_member_id,
            ms.prescription_id,
            ms.medicine_name,
            ms.dosage,
            ms.frequency,
            ms.times,
            ms.instructions,
            ms.start_date,
            ms.end_date,
            ms.refill_date,
            ms.total_quantity,
            ms.remaining_quantity,
            ms.is_active,
            ms.created_at,
            ms.updated_at,
            -- next_reminder_time: today + first time entry from the times JSONB array
            CASE
                WHEN ms.times IS NOT NULL
                     AND jsonb_array_length(ms.times) > 0
                THEN (
                    NOW()::DATE + (ms.times->>0)::TIME
                )::TIMESTAMPTZ
                ELSE NULL
            END AS next_reminder_time
        FROM medication_schedules ms
        WHERE ms.user_id   = p_user_id
          AND ms.is_active = TRUE
        ORDER BY ms.created_at DESC;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'fn_get_medication_schedules',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('user_id', p_user_id)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 21. sp_update_medication_schedule ─────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_update_medication_schedule(
    p_schedule_id  INTEGER,
    p_user_id      INTEGER,
    p_is_active    BOOLEAN,
    p_dosage       VARCHAR,
    p_frequency    VARCHAR,
    p_times        JSONB,
    p_instructions TEXT
)
RETURNS VOID AS $$
BEGIN
    UPDATE medication_schedules
    SET
        is_active    = COALESCE(p_is_active,    is_active),
        dosage       = COALESCE(p_dosage,       dosage),
        frequency    = COALESCE(p_frequency,    frequency),
        times        = COALESCE(p_times,        times),
        instructions = COALESCE(p_instructions, instructions),
        updated_at   = NOW()
    WHERE id      = p_schedule_id
      AND user_id = p_user_id;

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_update_medication_schedule',
        'SUCCESS',
        '00000',
        jsonb_build_object('schedule_id', p_schedule_id, 'user_id', p_user_id)
    );

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_update_medication_schedule',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('schedule_id', p_schedule_id, 'user_id', p_user_id)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 22. sp_delete_medication_schedule ─────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_delete_medication_schedule(
    p_schedule_id INTEGER,
    p_user_id     INTEGER
)
RETURNS VOID AS $$
BEGIN
    UPDATE medication_schedules
    SET is_active = FALSE
    WHERE id      = p_schedule_id
      AND user_id = p_user_id;

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_delete_medication_schedule',
        'SUCCESS',
        '00000',
        jsonb_build_object('schedule_id', p_schedule_id, 'user_id', p_user_id)
    );

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_delete_medication_schedule',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object('schedule_id', p_schedule_id, 'user_id', p_user_id)
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 23. sp_upsert_ai_conversation ─────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION sp_upsert_ai_conversation(
    p_user_id         INTEGER,
    p_conversation_id INTEGER,
    p_title           VARCHAR,
    p_context_type    VARCHAR,
    p_messages        JSONB,
    p_token_count     INTEGER
)
RETURNS TABLE(id INTEGER, updated_at TIMESTAMPTZ) AS $$
DECLARE
    v_id         INTEGER;
    v_updated_at TIMESTAMPTZ;
BEGIN
    IF p_conversation_id IS NULL THEN
        -- INSERT new conversation
        INSERT INTO ai_conversations (user_id, title, context_type, messages, token_count)
        VALUES (
            p_user_id,
            COALESCE(p_title, 'New Conversation'),
            COALESCE(p_context_type, 'general'),
            COALESCE(p_messages, '[]'::JSONB),
            COALESCE(p_token_count, 0)
        )
        RETURNING ai_conversations.id, ai_conversations.updated_at INTO v_id, v_updated_at;
    ELSE
        -- UPDATE existing conversation (security: check user_id ownership)
        UPDATE ai_conversations
        SET
            title        = COALESCE(p_title,        title),
            context_type = COALESCE(p_context_type, context_type),
            messages     = COALESCE(p_messages,     messages),
            token_count  = COALESCE(p_token_count,  token_count),
            updated_at   = NOW()
        WHERE id      = p_conversation_id
          AND user_id = p_user_id
        RETURNING ai_conversations.id, ai_conversations.updated_at INTO v_id, v_updated_at;

        IF v_id IS NULL THEN
            RAISE EXCEPTION 'Conversation % not found or does not belong to user %',
                p_conversation_id, p_user_id;
        END IF;
    END IF;

    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_upsert_ai_conversation',
        'SUCCESS',
        '00000',
        jsonb_build_object(
            'user_id',         p_user_id,
            'conversation_id', p_conversation_id
        )
    );

    RETURN QUERY SELECT v_id, v_updated_at;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'sp_upsert_ai_conversation',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object(
            'user_id',         p_user_id,
            'conversation_id', p_conversation_id
        )
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 24. fn_get_ai_conversation ────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION fn_get_ai_conversation(
    p_conversation_id INTEGER,
    p_user_id         INTEGER
)
RETURNS TABLE(
    id           INTEGER,
    user_id      INTEGER,
    title        VARCHAR,
    context_type VARCHAR,
    messages     JSONB,
    token_count  INTEGER,
    created_at   TIMESTAMPTZ,
    updated_at   TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
        SELECT
            ac.id,
            ac.user_id,
            ac.title,
            ac.context_type,
            ac.messages,
            ac.token_count,
            ac.created_at,
            ac.updated_at
        FROM ai_conversations ac
        WHERE ac.id      = p_conversation_id
          AND ac.user_id = p_user_id;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'fn_get_ai_conversation',
        SQLERRM,
        SQLSTATE,
        jsonb_build_object(
            'conversation_id', p_conversation_id,
            'user_id',         p_user_id
        )
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")

    # ── 25. fn_user_stats ─────────────────────────────────────────────────
    _sql("""
CREATE OR REPLACE FUNCTION fn_user_stats()
RETURNS TABLE(
    total_users         BIGINT,
    active_users        BIGINT,
    total_otps          BIGINT,
    total_records       BIGINT,
    total_metrics       BIGINT,
    total_conversations BIGINT
) AS $$
BEGIN
    RETURN QUERY
        SELECT
            (SELECT COUNT(*)::BIGINT FROM users)                  AS total_users,
            (SELECT COUNT(*)::BIGINT FROM users WHERE is_active)  AS active_users,
            (SELECT COUNT(*)::BIGINT FROM otps)                   AS total_otps,
            (SELECT COUNT(*)::BIGINT FROM medical_records)        AS total_records,
            (SELECT COUNT(*)::BIGINT FROM health_metrics)         AS total_metrics,
            (SELECT COUNT(*)::BIGINT FROM ai_conversations)       AS total_conversations;

EXCEPTION WHEN OTHERS THEN
    INSERT INTO db_error_logs (proc_name, error_message, error_state, input_params)
    VALUES (
        'fn_user_stats',
        SQLERRM,
        SQLSTATE,
        '{}'::JSONB
    );
    RAISE;
END;
$$ LANGUAGE plpgsql;
""")


# ===========================================================================
# DOWNGRADE
# ===========================================================================

def downgrade() -> None:
    # Drop all stored procedures / functions (in reverse order)
    for fn in [
        'fn_user_stats()',
        'fn_get_ai_conversation(INTEGER, INTEGER)',
        'sp_upsert_ai_conversation(INTEGER, INTEGER, VARCHAR, VARCHAR, JSONB, INTEGER)',
        'sp_delete_medication_schedule(INTEGER, INTEGER)',
        'sp_update_medication_schedule(INTEGER, INTEGER, BOOLEAN, VARCHAR, VARCHAR, JSONB, TEXT)',
        'fn_get_medication_schedules(INTEGER)',
        'sp_insert_medication_schedule(INTEGER, INTEGER, VARCHAR, VARCHAR, VARCHAR, JSONB, TEXT, DATE, DATE)',
        'fn_get_medical_records(INTEGER, VARCHAR)',
        'sp_insert_medical_record(INTEGER, INTEGER, VARCHAR, VARCHAR, TEXT, VARCHAR, INTEGER, VARCHAR, TEXT, DATE)',
        'fn_get_emergency_contacts(INTEGER)',
        'sp_insert_emergency_contact(INTEGER, VARCHAR, VARCHAR, VARCHAR)',
        'fn_get_health_summary(INTEGER)',
        'sp_insert_health_metric(INTEGER, INTEGER, VARCHAR, NUMERIC, NUMERIC, VARCHAR, TEXT)',
        'sp_delete_family_member(INTEGER, INTEGER)',
        'sp_update_family_member(INTEGER, INTEGER, VARCHAR, VARCHAR, INTEGER, VARCHAR, VARCHAR, JSONB, JSONB)',
        'fn_get_family_members(INTEGER)',
        'sp_insert_family_member(INTEGER, VARCHAR, VARCHAR, INTEGER, VARCHAR, VARCHAR, JSONB, JSONB)',
        'sp_update_user(INTEGER, VARCHAR, INTEGER, VARCHAR, VARCHAR, JSONB, JSONB)',
        'sp_insert_user(VARCHAR, VARCHAR, VARCHAR, INTEGER, VARCHAR, VARCHAR)',
        'fn_get_user_by_id(INTEGER)',
        'fn_get_user_by_identifier(VARCHAR)',
        'sp_expire_old_otps()',
        'sp_mark_otp_used(INTEGER)',
        'fn_get_valid_otps(VARCHAR, VARCHAR)',
        'sp_insert_otp(VARCHAR, VARCHAR, VARCHAR, VARCHAR, TIMESTAMPTZ)',
    ]:
        op.execute(sa.text(f"DROP FUNCTION IF EXISTS {fn} CASCADE"))

    # Drop logging table
    op.execute(sa.text("DROP TABLE IF EXISTS db_error_logs"))

    # Revert otps table changes
    op.execute(sa.text("ALTER TABLE otps DROP COLUMN IF EXISTS otp_hash"))
    op.execute(sa.text("ALTER TABLE otps ALTER COLUMN otp_code TYPE VARCHAR(10)"))
