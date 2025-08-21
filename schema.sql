-- Chaki System Core Database Schema
-- Phase 1: Infrastructure Foundation

-- Enable required extensions (idempotent)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS temporal_tables;
CREATE EXTENSION IF NOT EXISTS age;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create schemas for logical separation
CREATE SCHEMA IF NOT EXISTS chaki_core;
CREATE SCHEMA IF NOT EXISTS chaki_funds;
CREATE SCHEMA IF NOT EXISTS chaki_documents;
CREATE SCHEMA IF NOT EXISTS chaki_analytics;
CREATE SCHEMA IF NOT EXISTS chaki_temporal;

-- Set search path
SET search_path TO chaki_core, chaki_funds, chaki_documents, chaki_analytics, public;

-- =====================================================
-- Core Tables
-- =====================================================

-- Organizations (Investment Firms)
CREATE TABLE IF NOT EXISTS chaki_core.organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50) NOT NULL CHECK (type IN ('pension_fund', 'insurance', 'family_office', 'bank', 'other')),
    country_code CHAR(2) NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Users
CREATE TABLE IF NOT EXISTS chaki_core.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES chaki_core.organizations(id) ON DELETE CASCADE,
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL CHECK (role IN ('admin', 'analyst', 'viewer')),
    preferences JSONB DEFAULT '{}',
    last_login TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- Fund Tables
-- =====================================================

-- Fund Management Companies
CREATE TABLE IF NOT EXISTS chaki_funds.fund_managers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    aum_millions_eur DECIMAL(12, 2),
    founded_year INTEGER,
    headquarters_country CHAR(2),
    website VARCHAR(255),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Funds
CREATE TABLE IF NOT EXISTS chaki_funds.funds (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    fund_manager_id UUID REFERENCES chaki_funds.fund_managers(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    asset_class VARCHAR(50) NOT NULL,
    strategy VARCHAR(100),
    vintage_year INTEGER,
    target_size_millions_eur DECIMAL(12, 2),
    status VARCHAR(50) DEFAULT 'fundraising',
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Fund Ratings (12-factor methodology)
CREATE TABLE IF NOT EXISTS chaki_funds.fund_ratings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    fund_id UUID REFERENCES chaki_funds.funds(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES chaki_core.organizations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES chaki_core.users(id),
    
    -- 12 Factor Ratings (each 0-5 scale)
    track_record_score DECIMAL(2, 1) CHECK (track_record_score BETWEEN 0 AND 5),
    management_quality_score DECIMAL(2, 1) CHECK (management_quality_score BETWEEN 0 AND 5),
    investment_process_score DECIMAL(2, 1) CHECK (investment_process_score BETWEEN 0 AND 5),
    governance_score DECIMAL(2, 1) CHECK (governance_score BETWEEN 0 AND 5),
    reporting_score DECIMAL(2, 1) CHECK (reporting_score BETWEEN 0 AND 5),
    esg_score DECIMAL(2, 1) CHECK (esg_score BETWEEN 0 AND 5),
    infrastructure_score DECIMAL(2, 1) CHECK (infrastructure_score BETWEEN 0 AND 5),
    pipeline_score DECIMAL(2, 1) CHECK (pipeline_score BETWEEN 0 AND 5),
    exit_strategy_score DECIMAL(2, 1) CHECK (exit_strategy_score BETWEEN 0 AND 5),
    fundraising_score DECIMAL(2, 1) CHECK (fundraising_score BETWEEN 0 AND 5),
    risk_management_score DECIMAL(2, 1) CHECK (risk_management_score BETWEEN 0 AND 5),
    co_investment_score DECIMAL(2, 1) CHECK (co_investment_score BETWEEN 0 AND 5),
    
    -- Weighted Overall Score
    overall_score DECIMAL(3, 2) GENERATED ALWAYS AS (
        (track_record_score * 0.15 +
         management_quality_score * 0.15 +
         investment_process_score * 0.10 +
         governance_score * 0.10 +
         reporting_score * 0.08 +
         esg_score * 0.08 +
         infrastructure_score * 0.08 +
         pipeline_score * 0.08 +
         exit_strategy_score * 0.06 +
         fundraising_score * 0.06 +
         risk_management_score * 0.04 +
         co_investment_score * 0.02)
    ) STORED,
    
    rating_date DATE DEFAULT CURRENT_DATE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(fund_id, organization_id, rating_date)
);

-- =====================================================
-- Document Tables
-- =====================================================

-- Documents (PDFs, presentations, etc.)
CREATE TABLE IF NOT EXISTS chaki_documents.documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    fund_id UUID REFERENCES chaki_funds.funds(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES chaki_core.organizations(id) ON DELETE CASCADE,
    uploaded_by UUID REFERENCES chaki_core.users(id),
    
    filename VARCHAR(255) NOT NULL,
    document_type VARCHAR(50) NOT NULL,
    file_size_bytes BIGINT,
    storage_path VARCHAR(500),
    
    -- Extraction metadata
    extraction_status VARCHAR(50) DEFAULT 'pending',
    extraction_started_at TIMESTAMPTZ,
    extraction_completed_at TIMESTAMPTZ,
    extraction_error TEXT,
    
    -- Content
    raw_text TEXT,
    structured_data JSONB DEFAULT '{}',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Document Embeddings (for semantic search)
CREATE TABLE IF NOT EXISTS chaki_documents.document_embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID REFERENCES chaki_documents.documents(id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL,
    chunk_text TEXT NOT NULL,
    embedding vector(1536), -- OpenAI embeddings dimension
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(document_id, chunk_index)
);

-- Create vector index for similarity search
CREATE INDEX IF NOT EXISTS idx_document_embeddings_vector 
    ON chaki_documents.document_embeddings 
    USING ivfflat (embedding vector_cosine_ops);

-- =====================================================
-- Analytics Tables
-- =====================================================

-- Extraction Metrics
CREATE TABLE IF NOT EXISTS chaki_analytics.extraction_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID REFERENCES chaki_documents.documents(id) ON DELETE CASCADE,
    
    total_pages INTEGER,
    extracted_fields INTEGER,
    confidence_score DECIMAL(3, 2),
    processing_time_seconds INTEGER,
    
    model_used VARCHAR(100),
    model_confidence JSONB DEFAULT '{}',
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User Activity Log
CREATE TABLE IF NOT EXISTS chaki_analytics.activity_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES chaki_core.users(id) ON DELETE CASCADE,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id UUID,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- Temporal Tables (for versioning)
-- =====================================================

-- Create temporal version of fund_ratings
CREATE TABLE IF NOT EXISTS chaki_temporal.fund_ratings_history (
    LIKE chaki_funds.fund_ratings,
    valid_from TIMESTAMPTZ NOT NULL,
    valid_to TIMESTAMPTZ NOT NULL
);

-- =====================================================
-- Indexes for Performance
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_users_organization ON chaki_core.users(organization_id);
CREATE INDEX IF NOT EXISTS idx_funds_manager ON chaki_funds.funds(fund_manager_id);
CREATE INDEX IF NOT EXISTS idx_fund_ratings_fund ON chaki_funds.fund_ratings(fund_id);
CREATE INDEX IF NOT EXISTS idx_fund_ratings_org ON chaki_funds.fund_ratings(organization_id);
CREATE INDEX IF NOT EXISTS idx_documents_fund ON chaki_documents.documents(fund_id);
CREATE INDEX IF NOT EXISTS idx_documents_status ON chaki_documents.documents(extraction_status);
CREATE INDEX IF NOT EXISTS idx_activity_user ON chaki_analytics.activity_log(user_id);
CREATE INDEX IF NOT EXISTS idx_activity_created ON chaki_analytics.activity_log(created_at DESC);

-- =====================================================
-- Row Level Security (RLS) - Multi-tenant isolation
-- =====================================================

ALTER TABLE chaki_core.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE chaki_funds.fund_ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE chaki_documents.documents ENABLE ROW LEVEL SECURITY;

-- Users can only see their own organization's data
CREATE POLICY org_isolation_users ON chaki_core.users
    FOR ALL
    USING (organization_id = current_setting('app.current_organization')::UUID);

CREATE POLICY org_isolation_ratings ON chaki_funds.fund_ratings
    FOR ALL
    USING (organization_id = current_setting('app.current_organization')::UUID);

CREATE POLICY org_isolation_documents ON chaki_documents.documents
    FOR ALL
    USING (organization_id = current_setting('app.current_organization')::UUID);

-- =====================================================
-- Functions and Triggers
-- =====================================================

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION chaki_core.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update trigger to all tables with updated_at
CREATE TRIGGER update_organizations_updated_at BEFORE UPDATE ON chaki_core.organizations
    FOR EACH ROW EXECUTE FUNCTION chaki_core.update_updated_at();

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON chaki_core.users
    FOR EACH ROW EXECUTE FUNCTION chaki_core.update_updated_at();

CREATE TRIGGER update_fund_managers_updated_at BEFORE UPDATE ON chaki_funds.fund_managers
    FOR EACH ROW EXECUTE FUNCTION chaki_core.update_updated_at();

CREATE TRIGGER update_funds_updated_at BEFORE UPDATE ON chaki_funds.funds
    FOR EACH ROW EXECUTE FUNCTION chaki_core.update_updated_at();

CREATE TRIGGER update_fund_ratings_updated_at BEFORE UPDATE ON chaki_funds.fund_ratings
    FOR EACH ROW EXECUTE FUNCTION chaki_core.update_updated_at();

CREATE TRIGGER update_documents_updated_at BEFORE UPDATE ON chaki_documents.documents
    FOR EACH ROW EXECUTE FUNCTION chaki_core.update_updated_at();

-- =====================================================
-- Scheduled Jobs (pg_cron)
-- =====================================================

-- Clean up old activity logs (run daily at 2 AM)
SELECT cron.schedule(
    'cleanup-old-activity-logs',
    '0 2 * * *',
    $$DELETE FROM chaki_analytics.activity_log WHERE created_at < NOW() - INTERVAL '90 days'$$
);

-- Update extraction metrics summary (run hourly)
SELECT cron.schedule(
    'update-extraction-metrics',
    '0 * * * *',
    $$REFRESH MATERIALIZED VIEW CONCURRENTLY IF EXISTS chaki_analytics.extraction_summary$$
);

-- =====================================================
-- Initial Data and Validation
-- =====================================================

-- Create default organization for testing
INSERT INTO chaki_core.organizations (name, type, country_code, metadata)
VALUES ('Demo Investment Firm', 'pension_fund', 'DE', '{"demo": true}')
ON CONFLICT DO NOTHING;

-- Verify schema creation
DO $$
DECLARE
    schema_count INTEGER;
    table_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO schema_count
    FROM information_schema.schemata
    WHERE schema_name LIKE 'chaki_%';
    
    SELECT COUNT(*) INTO table_count
    FROM information_schema.tables
    WHERE table_schema LIKE 'chaki_%';
    
    RAISE NOTICE 'Chaki system initialized: % schemas, % tables', schema_count, table_count;
END
$$;