-- ============================================================
-- VitaPulse AI - Development Test Data
-- WARNING: Do NOT run in production.
-- Run after 06_seed_medicines.sql
-- ============================================================

\c VitaPulse_DB

-- Wrap everything in a transaction so we can roll back on error
BEGIN;

-- ─────────────────────────────────────────────
-- TEST USERS
-- passwords are NOT stored (OTP-based auth) — fcm_token is a fake dev token
-- ─────────────────────────────────────────────
INSERT INTO users (name, email, phone, age, gender, blood_group,
    health_conditions, allergies, lifestyle_preferences,
    fcm_token, is_active, is_verified)
VALUES
(
    'Aiden Mitchell',
    'aiden.mitchell@example.com.au',
    '+61412345001',
    38, 'Male', 'O+',
    '["Type 2 Diabetes", "Hypertension"]',
    '["Penicillin", "Sulfa drugs"]',
    '{"diet": "omnivore", "exercise": "moderate", "smoking": false, "alcohol": "occasional"}',
    'dev_fcm_token_aiden_001',
    TRUE, TRUE
),
(
    'Sophie Nguyen',
    'sophie.nguyen@example.com.au',
    '+61412345002',
    29, 'Female', 'A+',
    '["Asthma", "Seasonal Allergic Rhinitis"]',
    '["Aspirin", "Shellfish"]',
    '{"diet": "vegetarian", "exercise": "high", "smoking": false, "alcohol": "none"}',
    'dev_fcm_token_sophie_002',
    TRUE, TRUE
),
(
    'James Kowalski',
    'james.kowalski@example.com.au',
    '+61412345003',
    55, 'Male', 'B+',
    '["Hypercholesterolaemia", "Atrial Fibrillation", "GORD"]',
    '[]',
    '{"diet": "omnivore", "exercise": "low", "smoking": false, "alcohol": "social"}',
    'dev_fcm_token_james_003',
    TRUE, TRUE
),
(
    'Dev Test User',
    'devtest@vitapulse.local',
    '+61400000099',
    25, 'Other', NULL,
    '[]',
    '[]',
    '{}',
    'dev_fcm_token_devtest_099',
    TRUE, FALSE
);

-- ─────────────────────────────────────────────
-- FAMILY MEMBERS
-- ─────────────────────────────────────────────
INSERT INTO family_members (user_id, name, relationship, age, gender, blood_group,
    medical_conditions, allergies, notes, is_active)
SELECT u.id, 'Margaret Mitchell', 'Parent', 68, 'Female', 'O+',
    '["Osteoporosis", "Hypertension", "Hypothyroidism"]',
    '["Codeine"]',
    'Lives with Aiden. Takes morning medications with breakfast.',
    TRUE
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

INSERT INTO family_members (user_id, name, relationship, age, gender, blood_group,
    medical_conditions, allergies, notes, is_active)
SELECT u.id, 'Tom Mitchell', 'Spouse', 40, 'Male', 'A-',
    '[]',
    '["Latex"]',
    NULL,
    TRUE
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

INSERT INTO family_members (user_id, name, relationship, age, gender, blood_group,
    medical_conditions, allergies, notes, is_active)
SELECT u.id, 'Lily Nguyen', 'Child', 6, 'Female', 'A+',
    '["Asthma (mild)"]',
    '["Nuts"]',
    'Has Ventolin inhaler at school.',
    TRUE
FROM users u WHERE u.email = 'sophie.nguyen@example.com.au';

-- ─────────────────────────────────────────────
-- OTPs (already used / expired — safe test data)
-- ─────────────────────────────────────────────
INSERT INTO otps (identifier, otp_code, purpose, is_used, attempts, expires_at)
SELECT '+61412345001', '123456', 'auth', TRUE, 1,
    NOW() - INTERVAL '1 hour';

INSERT INTO otps (identifier, otp_code, purpose, is_used, attempts, expires_at)
SELECT 'sophie.nguyen@example.com.au', '654321', 'auth', TRUE, 1,
    NOW() - INTERVAL '2 hours';

-- ─────────────────────────────────────────────
-- MEDICAL RECORDS
-- ─────────────────────────────────────────────
INSERT INTO medical_records (user_id, record_type, title, file_url, file_name,
    file_size, file_type, notes, record_date, is_active)
SELECT u.id,
    'prescription', 'Metformin Prescription — Feb 2026',
    '/uploads/dev/aiden_metformin_rx.pdf',
    'aiden_metformin_rx.pdf',
    145678, 'pdf',
    'GP review at Westmead Medical Centre. Dose increased to 1000mg BD.',
    NOW() - INTERVAL '30 days',
    TRUE
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

INSERT INTO medical_records (user_id, record_type, title, file_url, file_name,
    file_size, file_type, notes, record_date, is_active)
SELECT u.id,
    'lab_report', 'HbA1c & Lipid Panel — Jan 2026',
    '/uploads/dev/aiden_bloods_jan2026.pdf',
    'aiden_bloods_jan2026.pdf',
    89234, 'pdf',
    'HbA1c 7.2%, LDL 3.1 mmol/L. Follow up in 3 months.',
    NOW() - INTERVAL '45 days',
    TRUE
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

INSERT INTO medical_records (user_id, record_type, title, file_url, file_name,
    file_size, file_type, notes, record_date, is_active)
SELECT u.id,
    'prescription', 'Ventolin Prescription',
    '/uploads/dev/sophie_ventolin_rx.pdf',
    'sophie_ventolin_rx.pdf',
    98765, 'pdf',
    NULL,
    NOW() - INTERVAL '60 days',
    TRUE
FROM users u WHERE u.email = 'sophie.nguyen@example.com.au';

-- ─────────────────────────────────────────────
-- PRESCRIPTIONS (OCR-extracted)
-- ─────────────────────────────────────────────
INSERT INTO prescriptions (user_id, medical_record_id, doctor_name, hospital,
    prescription_date, raw_ocr_text, extracted_medicines, ai_summary)
SELECT
    u.id,
    mr.id,
    'Dr. Emily Tan',
    'Westmead Medical Centre, Westmead NSW 2145',
    NOW() - INTERVAL '30 days',
    'PRESCRIPTION\nDr Emily Tan MBBS FRACGP\n...\nMetformin 1000mg twice daily with meals\nAtorvastatin 40mg once daily at night\nPerindopril 5mg once daily in morning',
    '[
        {"name": "Metformin", "dosage": "1000mg", "frequency": "twice daily", "duration": "ongoing", "instructions": "Take with meals"},
        {"name": "Atorvastatin", "dosage": "40mg", "frequency": "once daily", "duration": "ongoing", "instructions": "Take at night"},
        {"name": "Perindopril", "dosage": "5mg", "frequency": "once daily", "duration": "ongoing", "instructions": "Take in the morning"}
    ]',
    'Prescription for Type 2 diabetes and cardiovascular risk management. Three medications: Metformin 1000mg BD for blood sugar control, Atorvastatin 40mg nocte for cholesterol, and Perindopril 5mg mane for blood pressure. All are long-term medications requiring regular monitoring.'
FROM users u
JOIN medical_records mr ON mr.user_id = u.id AND mr.title LIKE '%Metformin%'
WHERE u.email = 'aiden.mitchell@example.com.au';

-- ─────────────────────────────────────────────
-- MEDICATION SCHEDULES (Reminders)
-- ─────────────────────────────────────────────
INSERT INTO medication_schedules (user_id, medicine_name, dosage, frequency, times,
    instructions, start_date, total_quantity, remaining_quantity, is_active)
SELECT u.id, 'Metformin', '1000mg', 'twice_daily',
    '["08:00", "20:00"]',
    'Take with meals. Do not skip doses.',
    CURRENT_DATE - INTERVAL '30 days',
    60, 18, TRUE
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

INSERT INTO medication_schedules (user_id, medicine_name, dosage, frequency, times,
    instructions, start_date, total_quantity, remaining_quantity, refill_date, is_active)
SELECT u.id, 'Atorvastatin', '40mg', 'daily',
    '["21:00"]',
    'Take at bedtime. Avoid grapefruit juice.',
    CURRENT_DATE - INTERVAL '30 days',
    30, 5,
    CURRENT_DATE + INTERVAL '5 days',
    TRUE
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

INSERT INTO medication_schedules (user_id, medicine_name, dosage, frequency, times,
    instructions, start_date, total_quantity, remaining_quantity, is_active)
SELECT u.id, 'Perindopril', '5mg', 'daily',
    '["07:30"]',
    'Take in the morning before breakfast.',
    CURRENT_DATE - INTERVAL '30 days',
    30, 14, TRUE
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

INSERT INTO medication_schedules (user_id, medicine_name, dosage, frequency, times,
    instructions, start_date, is_active)
SELECT u.id, 'Ventolin (Salbutamol)', '2 puffs', 'as_needed',
    '[]',
    'Use when experiencing wheeze or shortness of breath. Shake well before use.',
    CURRENT_DATE - INTERVAL '60 days',
    TRUE
FROM users u WHERE u.email = 'sophie.nguyen@example.com.au';

INSERT INTO medication_schedules (user_id, medicine_name, dosage, frequency, times,
    instructions, start_date, is_active)
SELECT u.id, 'Seretide 250/25', '2 puffs', 'twice_daily',
    '["08:00", "20:00"]',
    'Rinse mouth after each dose. Do NOT use as rescue inhaler.',
    CURRENT_DATE - INTERVAL '60 days',
    TRUE
FROM users u WHERE u.email = 'sophie.nguyen@example.com.au';

-- Margaret Mitchell's reminders (Aiden's family member)
INSERT INTO medication_schedules (user_id, family_member_id, medicine_name, dosage, frequency, times,
    instructions, start_date, is_active)
SELECT u.id, fm.id, 'Levothyroxine', '75mcg', 'daily',
    '["07:00"]',
    'Take 30 min before breakfast on empty stomach.',
    CURRENT_DATE - INTERVAL '180 days',
    TRUE
FROM users u
JOIN family_members fm ON fm.user_id = u.id AND fm.name = 'Margaret Mitchell'
WHERE u.email = 'aiden.mitchell@example.com.au';

-- ─────────────────────────────────────────────
-- HEALTH METRICS
-- ─────────────────────────────────────────────
-- Aiden's blood pressure (last 7 days, twice daily)
DO $$
DECLARE
    _uid INTEGER;
    i INTEGER;
BEGIN
    SELECT id INTO _uid FROM users WHERE email = 'aiden.mitchell@example.com.au';
    FOR i IN 0..6 LOOP
        -- Morning reading
        INSERT INTO health_metrics (user_id, metric_type, value, value2, unit, recorded_at)
        VALUES (_uid, 'blood_pressure_systolic',
            (130 + floor(random() * 15))::NUMERIC,
            (82 + floor(random() * 10))::NUMERIC,
            'mmHg',
            NOW() - ((i || ' days')::INTERVAL) - INTERVAL '8 hours');
        -- Evening reading
        INSERT INTO health_metrics (user_id, metric_type, value, value2, unit, recorded_at)
        VALUES (_uid, 'blood_pressure_systolic',
            (128 + floor(random() * 12))::NUMERIC,
            (80 + floor(random() * 8))::NUMERIC,
            'mmHg',
            NOW() - ((i || ' days')::INTERVAL) - INTERVAL '20 hours');
    END LOOP;
END;
$$;

-- Aiden's blood sugar (last 14 days, fasting)
DO $$
DECLARE
    _uid INTEGER;
    i INTEGER;
BEGIN
    SELECT id INTO _uid FROM users WHERE email = 'aiden.mitchell@example.com.au';
    FOR i IN 0..13 LOOP
        INSERT INTO health_metrics (user_id, metric_type, value, unit, notes, recorded_at)
        VALUES (_uid, 'blood_sugar',
            (6.2 + (random() * 1.5))::NUMERIC(10,1),
            'mmol/L',
            'Fasting reading',
            NOW() - ((i || ' days')::INTERVAL) - INTERVAL '7 hours');
    END LOOP;
END;
$$;

-- Aiden's weight and height (static)
INSERT INTO health_metrics (user_id, metric_type, value, unit, recorded_at)
SELECT u.id, 'weight', 89.5, 'kg', NOW() - INTERVAL '3 days'
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

INSERT INTO health_metrics (user_id, metric_type, value, unit, recorded_at)
SELECT u.id, 'height', 178.0, 'cm', NOW() - INTERVAL '3 days'
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

-- Sophie's heart rate (last 7 days, after morning run)
DO $$
DECLARE
    _uid INTEGER;
    i INTEGER;
BEGIN
    SELECT id INTO _uid FROM users WHERE email = 'sophie.nguyen@example.com.au';
    FOR i IN 0..6 LOOP
        INSERT INTO health_metrics (user_id, metric_type, value, unit, notes, recorded_at)
        VALUES (_uid, 'heart_rate',
            (68 + floor(random() * 20))::NUMERIC,
            'bpm',
            'Post morning run',
            NOW() - ((i || ' days')::INTERVAL) - INTERVAL '7 hours');
    END LOOP;
END;
$$;

-- Sophie's oxygen level
INSERT INTO health_metrics (user_id, metric_type, value, unit, recorded_at)
SELECT u.id, 'oxygen_level', 98.0, '%', NOW() - INTERVAL '1 day'
FROM users u WHERE u.email = 'sophie.nguyen@example.com.au';

-- ─────────────────────────────────────────────
-- EMERGENCY CONTACTS
-- ─────────────────────────────────────────────
INSERT INTO emergency_contacts (user_id, name, phone, relationship, is_primary)
SELECT u.id, 'Tom Mitchell', '+61498765001', 'Spouse', TRUE
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

INSERT INTO emergency_contacts (user_id, name, phone, relationship, is_primary)
SELECT u.id, 'Margaret Mitchell', '+61498765002', 'Parent', FALSE
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

INSERT INTO emergency_contacts (user_id, name, phone, relationship, is_primary)
SELECT u.id, 'Tran Nguyen', '+61498765003', 'Parent', TRUE
FROM users u WHERE u.email = 'sophie.nguyen@example.com.au';

-- ─────────────────────────────────────────────
-- AI CONVERSATIONS (sample history)
-- ─────────────────────────────────────────────
INSERT INTO ai_conversations (user_id, title, context_type, messages, token_count)
SELECT u.id,
    'Understanding my Metformin dosage',
    'prescription',
    '[
        {"role": "user", "content": "My doctor increased my Metformin to 1000mg twice daily. Is this normal?", "timestamp": "2026-02-10T09:15:00+11:00"},
        {"role": "assistant", "content": "Yes, 1000mg twice daily (2000mg total) is a very common maintenance dose for Metformin in managing Type 2 diabetes. It is generally well tolerated when taken with food, which also helps reduce any stomach discomfort. The dose increase suggests your doctor wants better blood sugar control...", "timestamp": "2026-02-10T09:15:03+11:00"},
        {"role": "user", "content": "What should I watch out for?", "timestamp": "2026-02-10T09:16:00+11:00"},
        {"role": "assistant", "content": "Key things to watch for with Metformin: 1) Digestive symptoms — nausea, diarrhoea or stomach pain especially when starting or increasing dose. Taking it with meals helps significantly. 2) Lactic acidosis — this is rare but serious. Symptoms include muscle pain, weakness, breathing difficulty, stomach pain, nausea. Seek emergency care immediately. 3) Vitamin B12 levels can drop with long-term use — ask your GP to check this annually.", "timestamp": "2026-02-10T09:16:05+11:00"}
    ]',
    850
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

INSERT INTO ai_conversations (user_id, title, context_type, messages, token_count)
SELECT u.id,
    'Asthma triggers and management',
    'health',
    '[
        {"role": "user", "content": "I have asthma and it''s been worse lately. What could be triggering it?", "timestamp": "2026-02-15T14:30:00+11:00"},
        {"role": "assistant", "content": "Common asthma triggers include: allergens (pollen, dust mites, pet dander, mould), respiratory infections, cold air, exercise, smoke and air pollution, certain medications (aspirin, NSAIDs, beta-blockers), strong scents or chemical fumes, and stress. Given you are in Australia and March is approaching, pollen levels are often high in spring and summer which can worsen seasonal asthma...", "timestamp": "2026-02-15T14:30:04+11:00"}
    ]',
    420
FROM users u WHERE u.email = 'sophie.nguyen@example.com.au';

-- ─────────────────────────────────────────────
-- NOTIFICATION LOGS (sample sent notifications)
-- ─────────────────────────────────────────────
INSERT INTO notification_logs (user_id, medication_schedule_id, notification_type,
    title, body, is_sent, sent_at, scheduled_at)
SELECT
    ms.user_id,
    ms.id,
    'reminder',
    'Time for Metformin',
    'Take 1000mg Metformin with your breakfast.',
    TRUE,
    NOW() - INTERVAL '8 hours',
    NOW() - INTERVAL '8 hours'
FROM medication_schedules ms
JOIN users u ON u.id = ms.user_id
WHERE u.email = 'aiden.mitchell@example.com.au'
  AND ms.medicine_name = 'Metformin'
LIMIT 1;

INSERT INTO notification_logs (user_id, medication_schedule_id, notification_type,
    title, body, is_sent, sent_at, scheduled_at)
SELECT
    ms.user_id,
    ms.id,
    'refill',
    'Refill Atorvastatin Soon',
    'You have only 5 tablets of Atorvastatin remaining. Refill due in 5 days.',
    TRUE,
    NOW() - INTERVAL '30 minutes',
    NOW() - INTERVAL '30 minutes'
FROM medication_schedules ms
JOIN users u ON u.id = ms.user_id
WHERE u.email = 'aiden.mitchell@example.com.au'
  AND ms.medicine_name = 'Atorvastatin'
LIMIT 1;

-- ─────────────────────────────────────────────
-- AUDIT LOG entries
-- ─────────────────────────────────────────────
INSERT INTO audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, metadata)
SELECT u.id, 'LOGIN', 'users', u.id, '203.24.140.1'::INET,
    'VitaPulseAI/1.0 (Android 14; Pixel 8)',
    '{"method": "otp", "identifier_type": "email"}'
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

INSERT INTO audit_logs (user_id, action, resource_type, ip_address, user_agent, metadata)
SELECT u.id, 'UPLOAD_MEDICAL_RECORD', 'medical_records', '203.24.140.1'::INET,
    'VitaPulseAI/1.0 (Android 14; Pixel 8)',
    '{"file_type": "pdf", "record_type": "prescription"}'
FROM users u WHERE u.email = 'aiden.mitchell@example.com.au';

-- ─────────────────────────────────────────────
-- VERIFY DATA
-- ─────────────────────────────────────────────
DO $$
DECLARE
    _users      INTEGER;
    _family     INTEGER;
    _records    INTEGER;
    _rx         INTEGER;
    _schedules  INTEGER;
    _metrics    INTEGER;
    _emergency  INTEGER;
    _conv       INTEGER;
BEGIN
    SELECT COUNT(*) INTO _users      FROM users;
    SELECT COUNT(*) INTO _family     FROM family_members;
    SELECT COUNT(*) INTO _records    FROM medical_records;
    SELECT COUNT(*) INTO _rx         FROM prescriptions;
    SELECT COUNT(*) INTO _schedules  FROM medication_schedules;
    SELECT COUNT(*) INTO _metrics    FROM health_metrics;
    SELECT COUNT(*) INTO _emergency  FROM emergency_contacts;
    SELECT COUNT(*) INTO _conv       FROM ai_conversations;

    RAISE NOTICE '══════════════════════════════════════════';
    RAISE NOTICE ' VitaPulse AI — Test Data Summary';
    RAISE NOTICE '══════════════════════════════════════════';
    RAISE NOTICE '  Users:               %', _users;
    RAISE NOTICE '  Family Members:      %', _family;
    RAISE NOTICE '  Medical Records:     %', _records;
    RAISE NOTICE '  Prescriptions:       %', _rx;
    RAISE NOTICE '  Medication Schedules:%', _schedules;
    RAISE NOTICE '  Health Metrics:      %', _metrics;
    RAISE NOTICE '  Emergency Contacts:  %', _emergency;
    RAISE NOTICE '  AI Conversations:    %', _conv;
    RAISE NOTICE '══════════════════════════════════════════';
END;
$$;

COMMIT;
