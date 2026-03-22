-- ============================================================
-- VitaPulse AI - Performance Indexes
-- Run after 02_create_tables.sql
-- ============================================================

\c VitaPulse_DB

-- ─────────────────────────────────────────────
-- USERS
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_users_email           ON users (email) WHERE email IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_phone           ON users (phone) WHERE phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_is_active       ON users (is_active) WHERE is_active = TRUE;

-- GIN index for JSONB health data (supports containment @>, key existence ?, etc.)
CREATE INDEX IF NOT EXISTS idx_users_health_conditions  ON users USING GIN (health_conditions);
CREATE INDEX IF NOT EXISTS idx_users_allergies          ON users USING GIN (allergies);

-- ─────────────────────────────────────────────
-- OTPs
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_otps_identifier      ON otps (identifier);
CREATE INDEX IF NOT EXISTS idx_otps_expires_at      ON otps (expires_at);
-- Partial: only look up unused, unexpired OTPs
CREATE INDEX IF NOT EXISTS idx_otps_active          ON otps (identifier, purpose, expires_at)
    WHERE is_used = FALSE;

-- ─────────────────────────────────────────────
-- FAMILY MEMBERS
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_family_user_id       ON family_members (user_id);
CREATE INDEX IF NOT EXISTS idx_family_active        ON family_members (user_id, is_active)
    WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_family_conditions    ON family_members USING GIN (medical_conditions);
CREATE INDEX IF NOT EXISTS idx_family_allergies     ON family_members USING GIN (allergies);

-- ─────────────────────────────────────────────
-- MEDICAL RECORDS
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_records_user_id      ON medical_records (user_id);
CREATE INDEX IF NOT EXISTS idx_records_family       ON medical_records (family_member_id)
    WHERE family_member_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_records_type         ON medical_records (user_id, record_type);
CREATE INDEX IF NOT EXISTS idx_records_active       ON medical_records (user_id, created_at DESC)
    WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_records_date         ON medical_records (user_id, record_date DESC)
    WHERE record_date IS NOT NULL;

-- ─────────────────────────────────────────────
-- PRESCRIPTIONS
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_rx_user_id           ON prescriptions (user_id);
CREATE INDEX IF NOT EXISTS idx_rx_family            ON prescriptions (family_member_id)
    WHERE family_member_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rx_record            ON prescriptions (medical_record_id)
    WHERE medical_record_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rx_created           ON prescriptions (user_id, created_at DESC);
-- GIN for querying extracted medicine names
CREATE INDEX IF NOT EXISTS idx_rx_medicines         ON prescriptions USING GIN (extracted_medicines);

-- ─────────────────────────────────────────────
-- MEDICINES  (core search indexes)
-- ─────────────────────────────────────────────

-- Full-text search using the pre-computed tsvector column
CREATE INDEX IF NOT EXISTS idx_medicines_search_vector
    ON medicines USING GIN (search_vector);

-- Trigram index for fuzzy / ILIKE search on medicine name
CREATE INDEX IF NOT EXISTS idx_medicines_name_trgm
    ON medicines USING GIN (name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_medicines_generic_trgm
    ON medicines USING GIN (generic_name gin_trgm_ops)
    WHERE generic_name IS NOT NULL;

-- Exact lookups
CREATE INDEX IF NOT EXISTS idx_medicines_barcode    ON medicines (barcode) WHERE barcode IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_medicines_atc        ON medicines (atc_code) WHERE atc_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_medicines_schedule   ON medicines (schedule);
CREATE INDEX IF NOT EXISTS idx_medicines_tga        ON medicines (tga_registered, schedule);

-- Brand names JSONB (for searches like "contains brand X")
CREATE INDEX IF NOT EXISTS idx_medicines_brands     ON medicines USING GIN (brand_names);

-- ─────────────────────────────────────────────
-- MEDICATION SCHEDULES
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_sched_user_id        ON medication_schedules (user_id);
CREATE INDEX IF NOT EXISTS idx_sched_family         ON medication_schedules (family_member_id)
    WHERE family_member_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sched_active         ON medication_schedules (user_id, is_active)
    WHERE is_active = TRUE;
-- Used by reminder engine: find schedules due today
CREATE INDEX IF NOT EXISTS idx_sched_dates          ON medication_schedules (start_date, end_date)
    WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_sched_refill         ON medication_schedules (user_id, refill_date)
    WHERE refill_date IS NOT NULL AND is_active = TRUE;
-- Times JSONB for querying schedules at a specific time
CREATE INDEX IF NOT EXISTS idx_sched_times          ON medication_schedules USING GIN (times);

-- ─────────────────────────────────────────────
-- HEALTH METRICS
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_metrics_user_id      ON health_metrics (user_id);
CREATE INDEX IF NOT EXISTS idx_metrics_family       ON health_metrics (family_member_id)
    WHERE family_member_id IS NOT NULL;
-- Time-series query: user + metric type over a date range
CREATE INDEX IF NOT EXISTS idx_metrics_trend        ON health_metrics (user_id, metric_type, recorded_at DESC);
-- Recent metrics (dashboard summary)
CREATE INDEX IF NOT EXISTS idx_metrics_recent       ON health_metrics (user_id, recorded_at DESC);

-- ─────────────────────────────────────────────
-- EMERGENCY CONTACTS
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_emergency_user       ON emergency_contacts (user_id);
CREATE INDEX IF NOT EXISTS idx_emergency_primary    ON emergency_contacts (user_id, is_primary)
    WHERE is_primary = TRUE;

-- ─────────────────────────────────────────────
-- AI CONVERSATIONS
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_ai_conv_user         ON ai_conversations (user_id);
CREATE INDEX IF NOT EXISTS idx_ai_conv_recent       ON ai_conversations (user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_conv_type         ON ai_conversations (user_id, context_type);

-- ─────────────────────────────────────────────
-- AUDIT LOGS
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_audit_user           ON audit_logs (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_action         ON audit_logs (action);
CREATE INDEX IF NOT EXISTS idx_audit_created        ON audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_resource       ON audit_logs (resource_type, resource_id)
    WHERE resource_type IS NOT NULL;

-- ─────────────────────────────────────────────
-- NOTIFICATION LOGS
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_notif_user           ON notification_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_notif_scheduled      ON notification_logs (scheduled_at)
    WHERE is_sent = FALSE AND scheduled_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notif_schedule_ref   ON notification_logs (medication_schedule_id)
    WHERE medication_schedule_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notif_type           ON notification_logs (user_id, notification_type);
