-- ============================================================
-- VitaPulse AI - Functions, Procedures & Triggers
-- Run after 04_views.sql
-- ============================================================

\c VitaPulse_DB

-- ─────────────────────────────────────────────
-- 1. AUTO-UPDATE updated_at TIMESTAMP
--    Generic trigger function used by multiple tables
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Attach trigger to all tables with updated_at
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'users', 'family_members', 'medication_schedules',
        'medicines', 'ai_conversations'
    ] LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_%s_updated_at ON %I;
             CREATE TRIGGER trg_%s_updated_at
                 BEFORE UPDATE ON %I
                 FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();',
            tbl, tbl, tbl, tbl
        );
    END LOOP;
END;
$$;

-- ─────────────────────────────────────────────
-- 2. MEDICINE FULL-TEXT SEARCH VECTOR UPDATE
--    Keeps medicines.search_vector in sync automatically
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_update_medicine_search_vector()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', COALESCE(NEW.name, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.generic_name, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.drug_class, '')), 'C') ||
        setweight(to_tsvector('english', COALESCE(NEW.composition, '')), 'D');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_medicines_search_vector ON medicines;
CREATE TRIGGER trg_medicines_search_vector
    BEFORE INSERT OR UPDATE OF name, generic_name, drug_class, composition
    ON medicines
    FOR EACH ROW EXECUTE FUNCTION fn_update_medicine_search_vector();

-- Backfill search vectors for any existing rows
UPDATE medicines SET updated_at = updated_at WHERE search_vector IS NULL;

-- ─────────────────────────────────────────────
-- 3. AUDIT LOG TRIGGER
--    Automatically writes to audit_logs on sensitive table changes
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    _action     TEXT;
    _user_id    INTEGER := NULL;
BEGIN
    _action := TG_OP;  -- INSERT / UPDATE / DELETE

    -- Try to extract user_id from the row (most tables have it)
    IF TG_OP = 'DELETE' THEN
        BEGIN
            _user_id := (OLD).user_id;
        EXCEPTION WHEN undefined_column THEN
            _user_id := NULL;
        END;

        INSERT INTO audit_logs (user_id, action, resource_type, resource_id, metadata)
        VALUES (_user_id, _action || '_' || TG_TABLE_NAME,
                TG_TABLE_NAME, OLD.id,
                jsonb_build_object('old', to_jsonb(OLD)));
        RETURN OLD;
    ELSE
        BEGIN
            _user_id := (NEW).user_id;
        EXCEPTION WHEN undefined_column THEN
            _user_id := NULL;
        END;

        INSERT INTO audit_logs (user_id, action, resource_type, resource_id, metadata)
        VALUES (_user_id, _action || '_' || TG_TABLE_NAME,
                TG_TABLE_NAME, NEW.id,
                CASE TG_OP
                    WHEN 'UPDATE' THEN jsonb_build_object('new', to_jsonb(NEW), 'old', to_jsonb(OLD))
                    ELSE jsonb_build_object('new', to_jsonb(NEW))
                END);
        RETURN NEW;
    END IF;
END;
$$;

-- Attach audit trigger to sensitive tables
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'medical_records', 'prescriptions', 'emergency_contacts'
    ] LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_%s_audit ON %I;
             CREATE TRIGGER trg_%s_audit
                 AFTER INSERT OR UPDATE OR DELETE ON %I
                 FOR EACH ROW EXECUTE FUNCTION fn_audit_trigger();',
            tbl, tbl, tbl, tbl
        );
    END LOOP;
END;
$$;

-- ─────────────────────────────────────────────
-- 4. CALCULATE BMI
--    fn_calculate_bmi(weight_kg, height_cm) → NUMERIC
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_calculate_bmi(
    p_weight_kg  NUMERIC,
    p_height_cm  NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    _height_m NUMERIC;
    _bmi      NUMERIC;
BEGIN
    IF p_weight_kg IS NULL OR p_height_cm IS NULL
       OR p_weight_kg <= 0 OR p_height_cm <= 0 THEN
        RETURN NULL;
    END IF;

    _height_m := p_height_cm / 100.0;
    _bmi := ROUND(p_weight_kg / (_height_m * _height_m), 1);
    RETURN _bmi;
END;
$$;

COMMENT ON FUNCTION fn_calculate_bmi IS
    'Returns BMI rounded to 1 decimal place. Returns NULL for invalid inputs.';

-- ─────────────────────────────────────────────
-- 5. BMI CATEGORY
--    fn_bmi_category(bmi) → TEXT (WHO / AU categories)
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_bmi_category(p_bmi NUMERIC)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_bmi IS NULL THEN RETURN NULL; END IF;
    RETURN CASE
        WHEN p_bmi < 18.5 THEN 'Underweight'
        WHEN p_bmi < 25.0 THEN 'Normal weight'
        WHEN p_bmi < 30.0 THEN 'Overweight'
        WHEN p_bmi < 35.0 THEN 'Obese Class I'
        WHEN p_bmi < 40.0 THEN 'Obese Class II'
        ELSE                    'Obese Class III'
    END;
END;
$$;

-- ─────────────────────────────────────────────
-- 6. BLOOD PRESSURE CLASSIFICATION
--    fn_bp_classification(systolic, diastolic) → TEXT (AU Heart Foundation)
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_bp_classification(
    p_systolic   INTEGER,
    p_diastolic  INTEGER
)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_systolic IS NULL OR p_diastolic IS NULL THEN RETURN NULL; END IF;
    RETURN CASE
        WHEN p_systolic < 90  OR p_diastolic < 60  THEN 'Low (Hypotension)'
        WHEN p_systolic < 120 AND p_diastolic < 80  THEN 'Normal'
        WHEN p_systolic < 130 AND p_diastolic < 80  THEN 'Elevated'
        WHEN p_systolic < 140 OR p_diastolic < 90   THEN 'High Stage 1'
        WHEN p_systolic < 180 OR p_diastolic < 120  THEN 'High Stage 2'
        ELSE                                              'Hypertensive Crisis'
    END;
END;
$$;

COMMENT ON FUNCTION fn_bp_classification IS
    'Classifies blood pressure per Australian Heart Foundation guidelines.';

-- ─────────────────────────────────────────────
-- 7. GET HEALTH TREND
--    Returns last N readings for a user+metric as a summary
--    fn_get_health_trend(user_id, metric_type, days_back)
--    → TABLE(recorded_at, value, value2, unit)
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_get_health_trend(
    p_user_id      INTEGER,
    p_metric_type  VARCHAR,
    p_days_back    INTEGER DEFAULT 30
)
RETURNS TABLE (
    recorded_at  TIMESTAMPTZ,
    value        NUMERIC,
    value2       NUMERIC,
    unit         VARCHAR,
    notes        TEXT
)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    SELECT hm.recorded_at, hm.value, hm.value2, hm.unit, hm.notes
    FROM health_metrics hm
    WHERE hm.user_id = p_user_id
      AND hm.metric_type = p_metric_type
      AND hm.recorded_at >= NOW() - (p_days_back || ' days')::INTERVAL
    ORDER BY hm.recorded_at ASC;
END;
$$;

COMMENT ON FUNCTION fn_get_health_trend IS
    'Returns time-series readings for a given health metric over the specified lookback period.';

-- ─────────────────────────────────────────────
-- 8. GET DUE REMINDERS
--    Returns schedules whose reminder time falls within ±5 min of now
--    Designed to be called by a cron job every 5 minutes
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_get_due_reminders(
    p_window_minutes INTEGER DEFAULT 5
)
RETURNS TABLE (
    schedule_id         INTEGER,
    user_id             INTEGER,
    fcm_token           VARCHAR,
    family_member_name  VARCHAR,
    medicine_name       VARCHAR,
    dosage              VARCHAR,
    instructions        TEXT,
    due_time            TEXT
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    _now_time   TEXT;
BEGIN
    _now_time := TO_CHAR(NOW() AT TIME ZONE 'Australia/Sydney', 'HH24:MI');

    RETURN QUERY
    SELECT
        ms.id,
        ms.user_id,
        u.fcm_token,
        fm.name,
        ms.medicine_name,
        ms.dosage,
        ms.instructions,
        t.reminder_time
    FROM medication_schedules ms
    JOIN users u ON u.id = ms.user_id AND u.is_active = TRUE
    LEFT JOIN family_members fm ON fm.id = ms.family_member_id
    -- Unnest the times JSON array (e.g. ["08:00","20:00"])
    CROSS JOIN LATERAL jsonb_array_elements_text(ms.times) AS t(reminder_time)
    WHERE ms.is_active = TRUE
      AND u.fcm_token IS NOT NULL
      AND (ms.start_date IS NULL OR ms.start_date <= CURRENT_DATE)
      AND (ms.end_date   IS NULL OR ms.end_date   >= CURRENT_DATE)
      -- Match reminders within the window
      AND ABS(
            EXTRACT(EPOCH FROM (
                TO_TIMESTAMP(t.reminder_time, 'HH24:MI')::TIME::INTERVAL
              - TO_TIMESTAMP(_now_time, 'HH24:MI')::TIME::INTERVAL
            ))
          ) <= p_window_minutes * 60;
END;
$$;

COMMENT ON FUNCTION fn_get_due_reminders IS
    'Returns medication schedules whose reminder time falls within ±N minutes of the current AEST time. '
    'Call every 5 minutes from the backend notification worker.';

-- ─────────────────────────────────────────────
-- 9. CLEAN EXPIRED OTPs
--    Procedure to purge OTPs older than 24 hours
-- ─────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE proc_clean_expired_otps()
LANGUAGE plpgsql AS $$
DECLARE
    _deleted INTEGER;
BEGIN
    DELETE FROM otps
    WHERE expires_at < NOW() - INTERVAL '24 hours'
       OR is_used = TRUE;

    GET DIAGNOSTICS _deleted = ROW_COUNT;
    RAISE NOTICE 'proc_clean_expired_otps: deleted % rows', _deleted;
END;
$$;

COMMENT ON PROCEDURE proc_clean_expired_otps IS
    'Deletes used or expired OTP records. Run daily via pg_cron or backend scheduler.';

-- ─────────────────────────────────────────────
-- 10. PURGE OLD AUDIT LOGS
--     Keeps audit_logs for last N days (default 365)
-- ─────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE proc_purge_audit_logs(p_retain_days INTEGER DEFAULT 365)
LANGUAGE plpgsql AS $$
DECLARE
    _deleted INTEGER;
BEGIN
    DELETE FROM audit_logs WHERE created_at < NOW() - (p_retain_days || ' days')::INTERVAL;
    GET DIAGNOSTICS _deleted = ROW_COUNT;
    RAISE NOTICE 'proc_purge_audit_logs: deleted % rows older than % days', _deleted, p_retain_days;
END;
$$;

COMMENT ON PROCEDURE proc_purge_audit_logs IS
    'Purges audit log entries older than the specified number of days. Default retention: 365 days.';

-- ─────────────────────────────────────────────
-- 11. MEDICINE FULL-TEXT SEARCH FUNCTION
--     Returns ranked medicine results for a search query
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_search_medicines(
    p_query      TEXT,
    p_limit      INTEGER DEFAULT 20,
    p_offset     INTEGER DEFAULT 0
)
RETURNS TABLE (
    id               INTEGER,
    name             VARCHAR,
    generic_name     VARCHAR,
    brand_names      JSONB,
    drug_class       VARCHAR,
    schedule         VARCHAR,
    schedule_label   TEXT,
    tga_registered   BOOLEAN,
    rank             REAL
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    _tsquery TSQUERY;
BEGIN
    -- Build a safe tsquery from user input (prefix matching for partial words)
    _tsquery := websearch_to_tsquery('english', p_query);

    RETURN QUERY
    SELECT
        m.id,
        m.name,
        m.generic_name,
        m.brand_names,
        m.drug_class,
        m.schedule,
        CASE m.schedule
            WHEN 'S2' THEN 'Pharmacy Only'
            WHEN 'S3' THEN 'Pharmacist Only'
            WHEN 'S4' THEN 'Prescription Only'
            WHEN 'S8' THEN 'Controlled Drug'
            WHEN 'S9' THEN 'Prohibited Substance'
            ELSE 'Unscheduled (OTC)'
        END,
        m.tga_registered,
        -- Combine full-text rank with trigram similarity for best results
        (ts_rank(m.search_vector, _tsquery) * 0.7
         + similarity(m.name, p_query) * 0.3)::REAL AS rank
    FROM medicines m
    WHERE m.search_vector @@ _tsquery
       OR m.name ILIKE '%' || p_query || '%'
       OR m.generic_name ILIKE '%' || p_query || '%'
    ORDER BY rank DESC, m.tga_registered DESC, m.name ASC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

COMMENT ON FUNCTION fn_search_medicines IS
    'Hybrid full-text + trigram medicine search. Returns results ranked by relevance. '
    'Falls back to ILIKE when the tsquery produces no matches.';

-- ─────────────────────────────────────────────
-- 12. USER STATS (admin dashboard helper)
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_user_stats()
RETURNS TABLE (
    total_users         BIGINT,
    active_users        BIGINT,
    verified_users      BIGINT,
    new_users_7d        BIGINT,
    new_users_30d       BIGINT,
    total_prescriptions BIGINT,
    total_records       BIGINT,
    total_reminders     BIGINT
)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT COUNT(*) FROM users)                                                    AS total_users,
        (SELECT COUNT(*) FROM users WHERE is_active = TRUE)                             AS active_users,
        (SELECT COUNT(*) FROM users WHERE is_verified = TRUE)                           AS verified_users,
        (SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '7 days')     AS new_users_7d,
        (SELECT COUNT(*) FROM users WHERE created_at >= NOW() - INTERVAL '30 days')    AS new_users_30d,
        (SELECT COUNT(*) FROM prescriptions)                                            AS total_prescriptions,
        (SELECT COUNT(*) FROM medical_records WHERE is_active = TRUE)                  AS total_records,
        (SELECT COUNT(*) FROM medication_schedules WHERE is_active = TRUE)             AS total_reminders;
END;
$$;

COMMENT ON FUNCTION fn_user_stats IS
    'Aggregate user and usage statistics for the admin dashboard.';
