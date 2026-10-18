-- ==============================================================================
-- DATABASE INITIALIZATION SCRIPT: All-in-One Donation & Crowdfunding Platform
-- Target RDBMS: PostgreSQL 15+ (Compatible with Neon Serverless Postgres)
-- Version: V1
-- ==============================================================================

-- Enable pgcrypto extension for UUID generation if needed
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------------------------
-- 1. TABLE: users
-- Stores donors, campaign owners, and platform administrators
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Performance index on email for high-throughput authentication queries
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_email ON users(email);

-- ------------------------------------------------------------------------------
-- 2. TABLE: campaigns
-- Crowdfunding campaigns tracking target goals, collections, and optimistic lock version
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS campaigns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    target_amount NUMERIC(19, 4) NOT NULL CHECK (target_amount > 0),
    collected_amount NUMERIC(19, 4) NOT NULL DEFAULT 0.0000 CHECK (collected_amount >= 0),
    status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',
    owner_id UUID NOT NULL,
    version BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_campaigns_owner FOREIGN KEY (owner_id) 
        REFERENCES users(id) ON DELETE CASCADE
);

-- Performance indexes for active campaign discovery and owner dashboards
CREATE INDEX IF NOT EXISTS idx_campaign_status ON campaigns(status);
CREATE INDEX IF NOT EXISTS idx_campaign_owner ON campaigns(owner_id);

-- ------------------------------------------------------------------------------
-- 3. TABLE: donations
-- Payment transactions linked to campaigns with Razorpay tracking
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS donations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    campaign_id UUID NOT NULL,
    donor_id UUID,
    donor_name VARCHAR(255),
    donor_email VARCHAR(255),
    amount NUMERIC(19, 4) NOT NULL CHECK (amount > 0),
    currency VARCHAR(10) NOT NULL DEFAULT 'INR',
    razorpay_order_id VARCHAR(255) NOT NULL UNIQUE,
    razorpay_payment_id VARCHAR(255),
    razorpay_signature VARCHAR(512),
    status VARCHAR(50) NOT NULL DEFAULT 'INITIATED',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_donations_campaign FOREIGN KEY (campaign_id) 
        REFERENCES campaigns(id) ON DELETE CASCADE,
    CONSTRAINT fk_donations_donor FOREIGN KEY (donor_id) 
        REFERENCES users(id) ON DELETE SET NULL
);

-- Indexes for signature verification handoffs, campaign metrics, and status queries
CREATE UNIQUE INDEX IF NOT EXISTS idx_donation_razorpay_order ON donations(razorpay_order_id);
CREATE INDEX IF NOT EXISTS idx_donation_campaign ON donations(campaign_id);
CREATE INDEX IF NOT EXISTS idx_donation_donor ON donations(donor_id);
CREATE INDEX IF NOT EXISTS idx_donation_status ON donations(status);

-- ------------------------------------------------------------------------------
-- 4. SEED DATA FOR IMMEDIATE SMOKE TESTING & DEMO
-- ------------------------------------------------------------------------------

-- Insert Admin User (Password: Admin@123, BCrypt encoded)
INSERT INTO users (id, name, email, password, role, created_at)
VALUES (
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'Platform Administrator',
    'admin@donationplatform.com',
    '$2a$10$wT0a0N2f91RjXq4WkWqT5OF4qG5q5y0qT/3N0w3m9z7bQ8m0v3k6q', -- BCrypt hash of 'Admin@123'
    'ROLE_ADMIN',
    CURRENT_TIMESTAMP
)
ON CONFLICT (email) DO NOTHING;

-- Insert Active Demo Campaign
INSERT INTO campaigns (id, title, description, target_amount, collected_amount, status, owner_id, version, created_at, updated_at)
VALUES (
    'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380b22',
    'Emergency Flood Relief & Clean Water Initiative',
    'Providing emergency sustenance kits, clean potable drinking water filtration units, and medical supplies to disaster-affected communities in river basin regions.',
    500000.0000,
    0.0000,
    'ACTIVE',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    0,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
)
ON CONFLICT (id) DO NOTHING;
