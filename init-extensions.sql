-- Initialize PostgreSQL Extensions for Chaki System
-- This file is run on container startup to enable all required extensions

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable vector similarity search (for embeddings)
CREATE EXTENSION IF NOT EXISTS vector;

-- Enable temporal tables (for versioning)
CREATE EXTENSION IF NOT EXISTS temporal_tables;

-- Enable Apache AGE (for graph queries) - Must come before pg_cron
CREATE EXTENSION IF NOT EXISTS age;
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- Enable scheduled jobs
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Enable cryptographic functions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Enable full text search configurations
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Create custom text search configuration for German
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_ts_config WHERE cfgname = 'german_unaccent'
    ) THEN
        CREATE TEXT SEARCH CONFIGURATION german_unaccent (COPY = german);
        ALTER TEXT SEARCH CONFIGURATION german_unaccent
            ALTER MAPPING FOR hword, hword_part, word
            WITH unaccent, german_stem;
    END IF;
END
$$;

-- Create extension check function
CREATE OR REPLACE FUNCTION check_extensions()
RETURNS TABLE (
    extension_name TEXT,
    version TEXT,
    is_enabled BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.extname::TEXT,
        e.extversion::TEXT,
        TRUE
    FROM pg_extension e
    WHERE e.extname IN (
        'uuid-ossp', 'vector', 'temporal_tables',
        'age', 'pg_cron', 'pgcrypto', 'unaccent'
    )
    ORDER BY e.extname;
END;
$$ LANGUAGE plpgsql;

-- Verify all critical extensions are loaded
DO $$
DECLARE
    missing_extensions TEXT[];
BEGIN
    SELECT array_agg(ext)
    INTO missing_extensions
    FROM unnest(ARRAY[
        'uuid-ossp', 'vector', 'temporal_tables',
        'age', 'pg_cron', 'pgcrypto', 'unaccent'
    ]) ext
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_extension WHERE extname = ext
    );
    
    IF array_length(missing_extensions, 1) > 0 THEN
        RAISE EXCEPTION 'Missing critical extensions: %', array_to_string(missing_extensions, ', ');
    END IF;
END
$$;

-- Set up pg_cron to run in the current database
UPDATE pg_database SET datname = current_database() WHERE datname = current_database();

-- Grant necessary permissions
GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA cron TO postgres;

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'All Chaki system extensions initialized successfully';
END
$$;