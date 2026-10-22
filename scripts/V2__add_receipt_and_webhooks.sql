-- ==============================================================================
-- DATABASE MIGRATION SCRIPT: V2 - 80G Tax-Deductible Receipts & Webhooks
-- Target RDBMS: PostgreSQL 15+ (Compatible with Neon Serverless Postgres)
-- ==============================================================================

-- 1. Alter donations table to store donor PAN for 80G tax exemptions
ALTER TABLE donations 
ADD COLUMN IF NOT EXISTS donor_pan VARCHAR(20);

-- 2. Create receipts table storing audit trail and generated PDF documents
CREATE TABLE IF NOT EXISTS receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    receipt_number VARCHAR(64) NOT NULL UNIQUE,
    donation_id UUID NOT NULL UNIQUE,
    campaign_title VARCHAR(255) NOT NULL,
    donor_name VARCHAR(255) NOT NULL,
    donor_pan VARCHAR(20),
    donor_email VARCHAR(255) NOT NULL,
    amount NUMERIC(19, 4) NOT NULL CHECK (amount > 0),
    pdf_blob BYTEA,
    issued_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_receipts_donation FOREIGN KEY (donation_id) 
        REFERENCES donations(id) ON DELETE CASCADE
);

-- 3. Create high-throughput query indexes
CREATE UNIQUE INDEX IF NOT EXISTS idx_receipt_number ON receipts(receipt_number);
CREATE UNIQUE INDEX IF NOT EXISTS idx_receipt_donation ON receipts(donation_id);
CREATE INDEX IF NOT EXISTS idx_receipt_donor_email ON receipts(donor_email);
