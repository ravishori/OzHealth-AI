-- ============================================================
-- VitaPulse AI - Database Creation Script
-- Run as superuser (postgres)
-- ============================================================

-- Create database
CREATE DATABASE VitaPulse_DB
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TEMPLATE = template0
    CONNECTION LIMIT = -1;

-- Connect to the new database before running subsequent scripts
\c VitaPulse_DB

-- Enable useful extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";       -- UUID generation
CREATE EXTENSION IF NOT EXISTS "pg_trgm";         -- Trigram similarity for fuzzy search
CREATE EXTENSION IF NOT EXISTS "unaccent";        -- Accent-insensitive search
CREATE EXTENSION IF NOT EXISTS "btree_gin";       -- GIN index support for btree types

-- Create search configuration for Australian English
CREATE TEXT SEARCH CONFIGURATION IF NOT EXISTS vitapulse_search (COPY = english);

COMMENT ON DATABASE VitaPulse_DB IS 'VitaPulse AI - Intelligent Health Companion for Australia';
