-- ============================================================
-- VitaPulse AI - Views
-- Run after 03_indexes.sql
-- ============================================================

\c VitaPulse_DB

-- ─────────────────────────────────────────────
-- 1. USER HEALTH SUMMARY
--    Quick overview of a user's current health profile
-- ─────────────────────────────────────────────
CREATE OR REPLACE VIEW v_user_health_summary AS
SELECT
    u.id                            AS user_id,
    u.name,
    u.email,
    u.phone,
    u.age,
    u.gender,
    u.blood_group,
    u.health_conditions,
    u.allergies,
    -- Counts
    (SELECT COUNT(*) FROM family_members fm WHERE fm.user_id = u.id AND fm.is_active) AS family_member_count,
    (SELECT COUNT(*) FROM medical_records mr WHERE mr.user_id = u.id AND mr.is_active) AS medical_record_count,
    (SELECT COUNT(*) FROM prescriptions p WHERE p.user_id = u.id) AS prescription_count,
    (SELECT COUNT(*) FROM medication_schedules ms WHERE ms.user_id = u.id AND ms.is_active) AS active_reminder_count,
    (SELECT COUNT(*) FROM emergency_contacts ec WHERE ec.user_id = u.id) AS emergency_contact_count,
    -- Latest vitals (most recent single reading per metric)
    (SELECT hm.value FROM health_metrics hm WHERE hm.user_id = u.id AND hm.metric_type = 'heart_rate'
        ORDER BY hm.recorded_at DESC LIMIT 1) AS latest_heart_rate,
    (SELECT hm.value FROM health_metrics hm WHERE hm.user_id = u.id AND hm.metric_type = 'blood_pressure_systolic'
        ORDER BY hm.recorded_at DESC LIMIT 1) AS latest_bp_systolic,
    (SELECT hm.value2 FROM health_metrics hm WHERE hm.user_id = u.id AND hm.metric_type = 'blood_pressure_systolic'
        ORDER BY hm.recorded_at DESC LIMIT 1) AS latest_bp_diastolic,
    (SELECT hm.value FROM health_metrics hm WHERE hm.user_id = u.id AND hm.metric_type = 'blood_sugar'
        ORDER BY hm.recorded_at DESC LIMIT 1) AS latest_blood_sugar,
    (SELECT hm.value FROM health_metrics hm WHERE hm.user_id = u.id AND hm.metric_type = 'weight'
        ORDER BY hm.recorded_at DESC LIMIT 1) AS latest_weight_kg,
    u.created_at,
    u.updated_at
FROM users u
WHERE u.is_active = TRUE;

COMMENT ON VIEW v_user_health_summary IS 'Consolidated health profile summary per active user';

-- ─────────────────────────────────────────────
-- 2. ACTIVE REMINDERS DUE TODAY
--    Used by the notification engine to find what to send
-- ─────────────────────────────────────────────
CREATE OR REPLACE VIEW v_active_reminders_today AS
SELECT
    ms.id                           AS schedule_id,
    ms.user_id,
    u.name                          AS user_name,
    u.fcm_token,
    ms.family_member_id,
    fm.name                         AS family_member_name,
    ms.medicine_name,
    ms.dosage,
    ms.frequency,
    ms.times,
    ms.instructions,
    ms.start_date,
    ms.end_date,
    ms.refill_date,
    ms.remaining_quantity,
    -- Flag if refill is needed soon (within 7 days)
    CASE
        WHEN ms.refill_date IS NOT NULL AND ms.refill_date <= CURRENT_DATE + INTERVAL '7 days'
        THEN TRUE ELSE FALSE
    END AS refill_due_soon
FROM medication_schedules ms
JOIN users u ON u.id = ms.user_id
LEFT JOIN family_members fm ON fm.id = ms.family_member_id
WHERE ms.is_active = TRUE
  AND u.is_active = TRUE
  AND u.fcm_token IS NOT NULL
  AND (ms.start_date IS NULL OR ms.start_date <= CURRENT_DATE)
  AND (ms.end_date IS NULL OR ms.end_date >= CURRENT_DATE);

COMMENT ON VIEW v_active_reminders_today IS 'Medication schedules active today, joined with user FCM token for push delivery';

-- ─────────────────────────────────────────────
-- 3. MEDICINE SEARCH VIEW
--    Combines all searchable fields for frontend search
-- ─────────────────────────────────────────────
CREATE OR REPLACE VIEW v_medicine_search AS
SELECT
    m.id,
    m.name,
    m.generic_name,
    m.brand_names,
    m.drug_class,
    m.dosage_forms,
    m.standard_dosage,
    m.schedule,
    m.tga_registered,
    m.tga_artg_number,
    m.pregnancy_category,
    m.atc_code,
    m.barcode,
    m.side_effects,
    m.contraindications,
    m.warnings,
    m.interactions,
    m.storage_instructions,
    -- Human-readable schedule label
    CASE m.schedule
        WHEN 'S2' THEN 'Pharmacy Only'
        WHEN 'S3' THEN 'Pharmacist Only'
        WHEN 'S4' THEN 'Prescription Only'
        WHEN 'S8' THEN 'Controlled Drug'
        WHEN 'S9' THEN 'Prohibited Substance'
        ELSE 'Unscheduled (OTC)'
    END AS schedule_label,
    -- Human-readable pregnancy category
    CASE m.pregnancy_category
        WHEN 'A'  THEN 'Safe — No fetal risk demonstrated'
        WHEN 'B1' THEN 'Limited data — Animal studies OK'
        WHEN 'B2' THEN 'Limited data — Animal studies inadequate'
        WHEN 'B3' THEN 'Limited data — Animal studies showed effects'
        WHEN 'C'  THEN 'Caution — Risk of fetal effects'
        WHEN 'D'  THEN 'Risk — Definite risk of fetal malformation'
        WHEN 'X'  THEN 'Contraindicated in pregnancy'
        ELSE NULL
    END AS pregnancy_category_label
FROM medicines m;

COMMENT ON VIEW v_medicine_search IS 'Medicine list with human-readable schedule and pregnancy category labels';

-- ─────────────────────────────────────────────
-- 4. RECENT HEALTH METRICS PER USER
--    Last 30 days, one row per user+metric_type for dashboard
-- ─────────────────────────────────────────────
CREATE OR REPLACE VIEW v_latest_health_metrics AS
SELECT DISTINCT ON (hm.user_id, hm.family_member_id, hm.metric_type)
    hm.id,
    hm.user_id,
    hm.family_member_id,
    hm.metric_type,
    hm.value,
    hm.value2,
    hm.unit,
    hm.notes,
    hm.recorded_at
FROM health_metrics hm
ORDER BY hm.user_id, hm.family_member_id, hm.metric_type, hm.recorded_at DESC;

COMMENT ON VIEW v_latest_health_metrics IS 'Most recent reading per user+member per metric type';

-- ─────────────────────────────────────────────
-- 5. PRESCRIPTION MEDICINES FLATTENED
--    Each extracted medicine becomes its own row (JSON unnested)
-- ─────────────────────────────────────────────
CREATE OR REPLACE VIEW v_prescription_medicines AS
SELECT
    p.id                            AS prescription_id,
    p.user_id,
    p.family_member_id,
    p.doctor_name,
    p.hospital,
    p.prescription_date,
    p.created_at,
    med_item ->> 'name'             AS medicine_name,
    med_item ->> 'dosage'           AS dosage,
    med_item ->> 'frequency'        AS frequency,
    med_item ->> 'duration'         AS duration,
    med_item ->> 'instructions'     AS instructions
FROM prescriptions p,
     jsonb_array_elements(p.extracted_medicines) AS med_item;

COMMENT ON VIEW v_prescription_medicines IS 'Flattened view: one row per medicine extracted from a prescription';

-- ─────────────────────────────────────────────
-- 6. REFILL ALERTS
--    Schedules where refill is needed within 7 days or stock is low
-- ─────────────────────────────────────────────
CREATE OR REPLACE VIEW v_refill_alerts AS
SELECT
    ms.id                           AS schedule_id,
    ms.user_id,
    u.name                          AS user_name,
    u.fcm_token,
    ms.medicine_name,
    ms.dosage,
    ms.remaining_quantity,
    ms.refill_date,
    CASE
        WHEN ms.refill_date IS NOT NULL THEN ms.refill_date - CURRENT_DATE
        ELSE NULL
    END AS days_until_refill,
    CASE
        WHEN ms.remaining_quantity IS NOT NULL AND ms.remaining_quantity <= 7 THEN 'low_stock'
        WHEN ms.refill_date IS NOT NULL AND ms.refill_date <= CURRENT_DATE + INTERVAL '7 days' THEN 'refill_due'
        ELSE 'ok'
    END AS alert_type
FROM medication_schedules ms
JOIN users u ON u.id = ms.user_id
WHERE ms.is_active = TRUE
  AND u.is_active = TRUE
  AND (
      (ms.remaining_quantity IS NOT NULL AND ms.remaining_quantity <= 7)
      OR
      (ms.refill_date IS NOT NULL AND ms.refill_date <= CURRENT_DATE + INTERVAL '7 days')
  );

COMMENT ON VIEW v_refill_alerts IS 'Medication schedules approaching refill date or with low remaining stock';

-- ─────────────────────────────────────────────
-- 7. AUDIT TRAIL (user-friendly)
-- ─────────────────────────────────────────────
CREATE OR REPLACE VIEW v_audit_trail AS
SELECT
    al.id,
    al.created_at,
    al.action,
    al.resource_type,
    al.resource_id,
    al.ip_address,
    u.name                          AS user_name,
    u.email                         AS user_email,
    al.metadata
FROM audit_logs al
LEFT JOIN users u ON u.id = al.user_id
ORDER BY al.created_at DESC;

COMMENT ON VIEW v_audit_trail IS 'Audit log joined with user details for admin reporting';
