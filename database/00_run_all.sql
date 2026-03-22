-- ============================================================
-- VitaPulse AI — Master Database Setup Script
-- Runs all scripts in order on a fresh PostgreSQL instance.
--
-- Usage (run as superuser, e.g. postgres):
--   psql -U postgres -f 00_run_all.sql
--
-- Or run individual files selectively:
--   01_create_database.sql  — Create DB + extensions
--   02_create_tables.sql    — DDL (tables, constraints, comments)
--   03_indexes.sql          — Performance indexes
--   04_views.sql            — Useful views
--   05_functions_procedures.sql — Functions, procedures, triggers
--   06_seed_medicines.sql   — Australian medicines reference data
--   07_seed_test_data.sql   — Development test users & records (skip in prod)
-- ============================================================

\echo ''
\echo '════════════════════════════════════════════════════════════'
\echo ' VitaPulse AI — Database Setup'
\echo ' Starting at: ' :DATETIME
\echo '════════════════════════════════════════════════════════════'

-- Step 1: Create database and extensions
\echo ''
\echo '[1/7] Creating database and extensions...'
\i 01_create_database.sql

-- Step 2: Create all tables
\echo ''
\echo '[2/7] Creating tables...'
\i 02_create_tables.sql

-- Step 3: Create indexes
\echo ''
\echo '[3/7] Creating indexes...'
\i 03_indexes.sql

-- Step 4: Create views
\echo ''
\echo '[4/7] Creating views...'
\i 04_views.sql

-- Step 5: Create functions, procedures & triggers
\echo ''
\echo '[5/7] Creating functions, procedures and triggers...'
\i 05_functions_procedures.sql

-- Step 6: Seed reference medicines data
\echo ''
\echo '[6/7] Seeding Australian medicines data...'
\i 06_seed_medicines.sql

-- Step 7: Seed development test data (comment out for production)
\echo ''
\echo '[7/7] Seeding development test data...'
\i 07_seed_test_data.sql

-- ──────────────────────────────────────────────────────────────
-- Verify setup
-- ──────────────────────────────────────────────────────────────
\c VitaPulse_DB

\echo ''
\echo '════════════════════════════════════════════════════════════'
\echo ' Setup complete! Final verification:'
\echo '════════════════════════════════════════════════════════════'

\echo ''
\echo 'Tables:'
SELECT tablename AS table_name,
       pg_size_pretty(pg_total_relation_size(quote_ident(tablename))) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

\echo ''
\echo 'Views:'
SELECT viewname FROM pg_views WHERE schemaname = 'public' ORDER BY viewname;

\echo ''
\echo 'Functions & Procedures:'
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
ORDER BY routine_type, routine_name;

\echo ''
\echo 'Row counts:'
SELECT
    'users'                 AS "table", COUNT(*) AS rows FROM users
UNION ALL SELECT 'family_members',      COUNT(*) FROM family_members
UNION ALL SELECT 'medicines',           COUNT(*) FROM medicines
UNION ALL SELECT 'medication_schedules',COUNT(*) FROM medication_schedules
UNION ALL SELECT 'health_metrics',      COUNT(*) FROM health_metrics
UNION ALL SELECT 'emergency_contacts',  COUNT(*) FROM emergency_contacts
UNION ALL SELECT 'ai_conversations',    COUNT(*) FROM ai_conversations
ORDER BY 1;

\echo ''
\echo '✓ VitaPulse AI database is ready.'
\echo '  Next steps:'
\echo '  1. cd ../backend && pip install -r requirements.txt'
\echo '  2. Set ANTHROPIC_API_KEY in backend/.env'
\echo '  3. uvicorn main:app --reload  (or docker-compose up)'
\echo '  4. API docs: http://localhost:8000/docs'
\echo ''
