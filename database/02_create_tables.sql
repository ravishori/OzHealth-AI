-- ============================================================
-- VitaPulse AI - Table Definitions
-- Run after 01_create_database.sql, connected to VitaPulse_DB
-- ============================================================

\c VitaPulse_DB

-- ─────────────────────────────────────────────
-- 1. USERS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id                      SERIAL PRIMARY KEY,
    name                    VARCHAR(255)    NOT NULL,
    email                   VARCHAR(255)    UNIQUE,
    phone                   VARCHAR(20)     UNIQUE,
    age                     SMALLINT        CHECK (age > 0 AND age < 150),
    gender                  VARCHAR(20)     CHECK (gender IN ('Male', 'Female', 'Other', 'Prefer not to say')),
    blood_group             VARCHAR(10)     CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    health_conditions       JSONB           NOT NULL DEFAULT '[]',
    allergies               JSONB           NOT NULL DEFAULT '[]',
    lifestyle_preferences   JSONB           NOT NULL DEFAULT '{}',
    fcm_token               VARCHAR(500),
    profile_image_url       VARCHAR(1000),
    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
    is_verified             BOOLEAN         NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ,
    CONSTRAINT chk_users_contact CHECK (email IS NOT NULL OR phone IS NOT NULL)
);

COMMENT ON TABLE users IS 'Registered app users';
COMMENT ON COLUMN users.health_conditions IS 'JSON array of health condition strings';
COMMENT ON COLUMN users.allergies IS 'JSON array of allergy strings';

-- ─────────────────────────────────────────────
-- 2. OTPs
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS otps (
    id          SERIAL PRIMARY KEY,
    identifier  VARCHAR(255)    NOT NULL,   -- email or phone
    otp_code    VARCHAR(10)     NOT NULL,
    purpose     VARCHAR(50)     NOT NULL DEFAULT 'auth' CHECK (purpose IN ('auth', 'register', 'reset')),
    is_used     BOOLEAN         NOT NULL DEFAULT FALSE,
    attempts    SMALLINT        NOT NULL DEFAULT 0,
    expires_at  TIMESTAMPTZ     NOT NULL,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE otps IS 'One-time passwords for authentication';

-- ─────────────────────────────────────────────
-- 3. FAMILY MEMBERS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS family_members (
    id                  SERIAL PRIMARY KEY,
    user_id             INTEGER         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name                VARCHAR(255)    NOT NULL,
    relationship        VARCHAR(100)    CHECK (relationship IN ('Self','Spouse','Parent','Child','Sibling','Grandparent','Grandchild','Other')),
    age                 SMALLINT        CHECK (age > 0 AND age < 150),
    gender              VARCHAR(20)     CHECK (gender IN ('Male', 'Female', 'Other')),
    blood_group         VARCHAR(10)     CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    medical_conditions  JSONB           NOT NULL DEFAULT '[]',
    allergies           JSONB           NOT NULL DEFAULT '[]',
    notes               TEXT,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ
);

COMMENT ON TABLE family_members IS 'Family members managed under a user account';

-- ─────────────────────────────────────────────
-- 4. MEDICAL RECORDS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS medical_records (
    id                  SERIAL PRIMARY KEY,
    user_id             INTEGER         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_member_id    INTEGER         REFERENCES family_members(id) ON DELETE SET NULL,
    record_type         VARCHAR(100)    NOT NULL CHECK (record_type IN ('prescription','lab_report','radiology','discharge_summary','other')),
    title               VARCHAR(500),
    file_url            VARCHAR(1000)   NOT NULL,
    file_name           VARCHAR(500)    NOT NULL,
    file_size           INTEGER         CHECK (file_size > 0),
    file_type           VARCHAR(50)     CHECK (file_type IN ('pdf','jpg','jpeg','png','heic')),
    notes               TEXT,
    record_date         TIMESTAMPTZ,
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE medical_records IS 'Uploaded medical documents (prescriptions, lab reports, etc.)';

-- ─────────────────────────────────────────────
-- 5. PRESCRIPTIONS (OCR extracted data)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS prescriptions (
    id                  SERIAL PRIMARY KEY,
    user_id             INTEGER         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    medical_record_id   INTEGER         REFERENCES medical_records(id) ON DELETE SET NULL,
    family_member_id    INTEGER         REFERENCES family_members(id) ON DELETE SET NULL,
    doctor_name         VARCHAR(255),
    hospital            VARCHAR(500),
    prescription_date   TIMESTAMPTZ,
    raw_ocr_text        TEXT,
    extracted_medicines JSONB           NOT NULL DEFAULT '[]',
    -- [{name, dosage, frequency, duration, instructions}]
    ai_summary          TEXT,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE prescriptions IS 'OCR-extracted prescription data with AI analysis';
COMMENT ON COLUMN prescriptions.extracted_medicines IS 'AI-extracted medicine list: [{name, dosage, frequency, duration, instructions}]';

-- ─────────────────────────────────────────────
-- 6. MEDICINES (TGA Australia database)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS medicines (
    id                      SERIAL PRIMARY KEY,
    name                    VARCHAR(500)    NOT NULL,
    generic_name            VARCHAR(500),
    brand_names             JSONB           NOT NULL DEFAULT '[]',
    composition             TEXT,
    drug_class              VARCHAR(255),
    dosage_forms            JSONB           NOT NULL DEFAULT '[]',   -- ['tablet','capsule','syrup']
    standard_dosage         TEXT,
    side_effects            TEXT,
    interactions            TEXT,
    contraindications       TEXT,
    warnings                TEXT,
    storage_instructions    TEXT,
    pregnancy_category      VARCHAR(10),    -- A, B1, B2, B3, C, D, X (AU TGA categories)
    barcode                 VARCHAR(100)    UNIQUE,
    tga_registered          BOOLEAN         NOT NULL DEFAULT FALSE,
    tga_artg_number         VARCHAR(50),    -- Australian Register of Therapeutic Goods number
    schedule                VARCHAR(10)     CHECK (schedule IN ('Unscheduled','S2','S3','S4','S8','S9')),
    -- AU Poisons Schedule: S2=Pharmacy, S3=Pharmacist, S4=Prescription, S8=Controlled, S9=Prohibited
    atc_code                VARCHAR(20),    -- WHO Anatomical Therapeutic Chemical code
    search_vector           TSVECTOR,       -- Full-text search vector
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ
);

COMMENT ON TABLE medicines IS 'Australian medicines database (TGA-aligned)';
COMMENT ON COLUMN medicines.schedule IS 'AU Poisons Schedule: S2=Pharmacy Only, S3=Pharmacist Only, S4=Prescription Only, S8=Controlled Drug';
COMMENT ON COLUMN medicines.tga_artg_number IS 'Australian Register of Therapeutic Goods (ARTG) entry number';
COMMENT ON COLUMN medicines.pregnancy_category IS 'TGA pregnancy category: A=Safe, B1/B2/B3=Limited data, C=Risk, D=Definite risk, X=Contraindicated';

-- ─────────────────────────────────────────────
-- 7. MEDICATION SCHEDULES (Reminders)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS medication_schedules (
    id                  SERIAL PRIMARY KEY,
    user_id             INTEGER         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_member_id    INTEGER         REFERENCES family_members(id) ON DELETE SET NULL,
    prescription_id     INTEGER         REFERENCES prescriptions(id) ON DELETE SET NULL,
    medicine_name       VARCHAR(500)    NOT NULL,
    dosage              VARCHAR(200),
    frequency           VARCHAR(100)    NOT NULL CHECK (frequency IN ('daily','twice_daily','three_times_daily','four_times_daily','weekly','fortnightly','monthly','as_needed')),
    times               JSONB           NOT NULL DEFAULT '[]',      -- ["08:00","20:00"]
    instructions        TEXT,
    start_date          DATE,
    end_date            DATE,
    refill_date         DATE,
    total_quantity      INTEGER         CHECK (total_quantity >= 0),
    remaining_quantity  INTEGER         CHECK (remaining_quantity >= 0),
    is_active           BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ,
    CONSTRAINT chk_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

COMMENT ON TABLE medication_schedules IS 'Medication reminder schedules for users and family members';

-- ─────────────────────────────────────────────
-- 8. HEALTH METRICS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS health_metrics (
    id                  SERIAL PRIMARY KEY,
    user_id             INTEGER         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_member_id    INTEGER         REFERENCES family_members(id) ON DELETE SET NULL,
    metric_type         VARCHAR(100)    NOT NULL CHECK (metric_type IN (
                            'blood_pressure_systolic',
                            'blood_pressure_diastolic',
                            'blood_sugar',
                            'heart_rate',
                            'oxygen_level',
                            'weight',
                            'height',
                            'bmi',
                            'temperature',
                            'cholesterol_total',
                            'cholesterol_hdl',
                            'cholesterol_ldl'
                        )),
    value               NUMERIC(10,2)   NOT NULL,
    value2              NUMERIC(10,2),  -- For BP: diastolic value
    unit                VARCHAR(50),
    notes               TEXT,
    recorded_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE health_metrics IS 'User health vitals and measurements over time';
COMMENT ON COLUMN health_metrics.value2 IS 'Secondary value, used for diastolic BP reading';

-- ─────────────────────────────────────────────
-- 9. EMERGENCY CONTACTS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS emergency_contacts (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            VARCHAR(255)    NOT NULL,
    phone           VARCHAR(20)     NOT NULL,
    relationship    VARCHAR(100),
    is_primary      BOOLEAN         NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE emergency_contacts IS 'Emergency contacts for SOS alerting';

-- ─────────────────────────────────────────────
-- 10. AI CONVERSATIONS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_conversations (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           VARCHAR(500),
    messages        JSONB           NOT NULL DEFAULT '[]',
    -- [{role, content, timestamp}]
    context_type    VARCHAR(100)    DEFAULT 'general' CHECK (context_type IN ('general','prescription','medicine','health','nutrition','exercise')),
    token_count     INTEGER         DEFAULT 0,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ
);

COMMENT ON TABLE ai_conversations IS 'AI health assistant conversation history';
COMMENT ON COLUMN ai_conversations.messages IS 'Message array: [{role: user|assistant, content: string, timestamp: ISO8601}]';

-- ─────────────────────────────────────────────
-- 11. AUDIT LOG
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_logs (
    id              BIGSERIAL PRIMARY KEY,
    user_id         INTEGER         REFERENCES users(id) ON DELETE SET NULL,
    action          VARCHAR(100)    NOT NULL,   -- LOGIN, UPLOAD, OTP_SENT, SOS_TRIGGERED, etc.
    resource_type   VARCHAR(100),
    resource_id     INTEGER,
    ip_address      INET,
    user_agent      TEXT,
    metadata        JSONB           DEFAULT '{}',
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE audit_logs IS 'Security and activity audit trail';

-- ─────────────────────────────────────────────
-- 12. NOTIFICATION LOGS
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notification_logs (
    id                      SERIAL PRIMARY KEY,
    user_id                 INTEGER         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    medication_schedule_id  INTEGER         REFERENCES medication_schedules(id) ON DELETE SET NULL,
    notification_type       VARCHAR(50)     NOT NULL CHECK (notification_type IN ('reminder','refill','appointment','sos','system')),
    title                   VARCHAR(255)    NOT NULL,
    body                    TEXT,
    is_sent                 BOOLEAN         NOT NULL DEFAULT FALSE,
    sent_at                 TIMESTAMPTZ,
    scheduled_at            TIMESTAMPTZ,
    fcm_message_id          VARCHAR(255),
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE notification_logs IS 'Push notification delivery log';
