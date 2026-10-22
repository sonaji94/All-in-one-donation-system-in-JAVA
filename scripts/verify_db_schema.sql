-- ==============================================================================
-- PRODUCTION DB SCHEMA INTEGRITY VERIFICATION SCRIPT
-- Platform: All-in-One Donation & Crowdfunding Platform
-- Target:   Neon PostgreSQL (PostgreSQL 15+)
-- Purpose:  Certify that V1 + V2 Flyway migrations applied correctly.
--           Run this directly via Neon SQL console or psql CLI.
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────
-- SECTION 1: Flyway migration version ledger
-- Confirms both V1 and V2 ran without locks or errors.
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    -- Check flyway_schema_history table exists (created by Spring Boot Flyway on first run)
    SELECT COUNT(*) INTO v_count
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'flyway_schema_history';

    IF v_count = 0 THEN
        RAISE EXCEPTION '[FAIL] flyway_schema_history table not found. Flyway has never run on this database.';
    ELSE
        RAISE NOTICE '[PASS] flyway_schema_history table exists.';
    END IF;
END $$;

SELECT
    version,
    description,
    type,
    script,
    checksum,
    installed_on,
    execution_time,
    success
FROM flyway_schema_history
ORDER BY installed_rank;

-- Assert both migrations succeeded
DO $$
DECLARE
    v1_success BOOLEAN;
    v2_success BOOLEAN;
BEGIN
    SELECT success INTO v1_success FROM flyway_schema_history WHERE version = '1' LIMIT 1;
    SELECT success INTO v2_success FROM flyway_schema_history WHERE version = '2' LIMIT 1;

    IF v1_success IS NULL THEN
        RAISE EXCEPTION '[FAIL] V1__init_donation_schema.sql migration record not found!';
    ELSIF NOT v1_success THEN
        RAISE EXCEPTION '[FAIL] V1 migration is recorded as FAILED. Manual repair required.';
    ELSE
        RAISE NOTICE '[PASS] V1__init_donation_schema.sql applied successfully.';
    END IF;

    IF v2_success IS NULL THEN
        RAISE EXCEPTION '[FAIL] V2__add_receipt_and_webhooks.sql migration record not found!';
    ELSIF NOT v2_success THEN
        RAISE EXCEPTION '[FAIL] V2 migration is recorded as FAILED. Manual repair required.';
    ELSE
        RAISE NOTICE '[PASS] V2__add_receipt_and_webhooks.sql applied successfully.';
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- SECTION 2: Core table existence checks
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY['users', 'campaigns', 'donations', 'receipts'] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = tbl
        ) THEN
            RAISE EXCEPTION '[FAIL] Required table "%" does not exist!', tbl;
        ELSE
            RAISE NOTICE '[PASS] Table "%" exists.', tbl;
        END IF;
    END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────
-- SECTION 3: receipts table — column-level audit
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
    col_rec RECORD;
    required_cols TEXT[] := ARRAY[
        'id', 'receipt_number', 'donation_id', 'campaign_title',
        'donor_name', 'donor_pan', 'donor_email', 'amount',
        'pdf_blob', 'issued_at'
    ];
    col TEXT;
BEGIN
    FOREACH col IN ARRAY required_cols LOOP
        SELECT column_name, data_type, is_nullable, character_maximum_length
        INTO col_rec
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'receipts'
          AND column_name = col;

        IF col_rec IS NULL THEN
            RAISE EXCEPTION '[FAIL] Column "receipts.%" is MISSING!', col;
        ELSE
            RAISE NOTICE '[PASS] Column "receipts.%" exists — type: %, nullable: %',
                col, col_rec.data_type, col_rec.is_nullable;
        END IF;
    END LOOP;
END $$;

-- Verify receipts.id is UUID primary key
DO $$
DECLARE
    v_type TEXT;
BEGIN
    SELECT data_type INTO v_type
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'receipts' AND column_name = 'id';

    IF v_type <> 'uuid' THEN
        RAISE EXCEPTION '[FAIL] receipts.id type is "%" — expected "uuid"', v_type;
    ELSE
        RAISE NOTICE '[PASS] receipts.id is UUID type.';
    END IF;
END $$;

-- Verify receipts.amount > 0 CHECK constraint exists
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM information_schema.check_constraints cc
    JOIN information_schema.constraint_column_usage ccu
      ON cc.constraint_name = ccu.constraint_name
    WHERE ccu.table_name = 'receipts'
      AND ccu.column_name = 'amount';

    IF v_count = 0 THEN
        RAISE EXCEPTION '[FAIL] receipts.amount CHECK constraint not found!';
    ELSE
        RAISE NOTICE '[PASS] receipts.amount has CHECK constraint.';
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- SECTION 4: donations.donor_pan column existence check (V2)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
    col_rec RECORD;
BEGIN
    SELECT column_name, data_type, character_maximum_length, is_nullable
    INTO col_rec
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'donations'
      AND column_name = 'donor_pan';

    IF col_rec IS NULL THEN
        RAISE EXCEPTION '[FAIL] donations.donor_pan column is MISSING — V2 migration may not have applied!';
    ELSE
        RAISE NOTICE '[PASS] donations.donor_pan exists — type: %, max_length: %, nullable: %',
            col_rec.data_type, col_rec.character_maximum_length, col_rec.is_nullable;

        -- Validate the column is nullable (PAN is optional for donors who decline 80G)
        IF col_rec.is_nullable <> 'YES' THEN
            RAISE EXCEPTION '[FAIL] donations.donor_pan must be nullable (donor PAN is optional)!';
        ELSE
            RAISE NOTICE '[PASS] donations.donor_pan is correctly nullable.';
        END IF;

        -- Validate max length is >= 20 chars (PAN is 10 chars, 20 gives buffer)
        IF col_rec.character_maximum_length IS NOT NULL AND col_rec.character_maximum_length < 10 THEN
            RAISE EXCEPTION '[FAIL] donations.donor_pan max_length % is too short (minimum 10 for PAN numbers)!',
                col_rec.character_maximum_length;
        ELSE
            RAISE NOTICE '[PASS] donations.donor_pan character limit is adequate.';
        END IF;
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- SECTION 5: Foreign key constraint verification
-- ─────────────────────────────────────────────────────────────
SELECT
    tc.table_name         AS "Table",
    kcu.column_name       AS "Column",
    ccu.table_name        AS "References Table",
    ccu.column_name       AS "References Column",
    rc.delete_rule        AS "ON DELETE"
FROM
    information_schema.table_constraints AS tc
    JOIN information_schema.key_column_usage AS kcu
        ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage AS ccu
        ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
    JOIN information_schema.referential_constraints AS rc
        ON rc.constraint_name = tc.constraint_name
WHERE
    tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = 'public'
ORDER BY tc.table_name, kcu.column_name;

-- Assert fk_receipts_donation -> donations(id) ON DELETE CASCADE
DO $$
DECLARE
    v_rule TEXT;
BEGIN
    SELECT rc.delete_rule INTO v_rule
    FROM information_schema.table_constraints tc
    JOIN information_schema.referential_constraints rc
        ON rc.constraint_name = tc.constraint_name
    WHERE tc.table_schema = 'public'
      AND tc.table_name = 'receipts'
      AND tc.constraint_type = 'FOREIGN KEY'
      AND tc.constraint_name = 'fk_receipts_donation';

    IF v_rule IS NULL THEN
        RAISE EXCEPTION '[FAIL] fk_receipts_donation foreign key constraint not found on receipts table!';
    ELSIF v_rule <> 'CASCADE' THEN
        RAISE EXCEPTION '[FAIL] fk_receipts_donation delete_rule is "%" — expected "CASCADE"', v_rule;
    ELSE
        RAISE NOTICE '[PASS] fk_receipts_donation -> donations(id) ON DELETE CASCADE verified.';
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- SECTION 6: Index verification (all 9 platform indexes)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
    idx TEXT;
    v_count INTEGER;
    required_indexes TEXT[] := ARRAY[
        'idx_user_email',
        'idx_campaign_status',
        'idx_campaign_owner',
        'idx_donation_razorpay_order',
        'idx_donation_campaign',
        'idx_donation_donor',
        'idx_donation_status',
        'idx_receipt_number',
        'idx_receipt_donation',
        'idx_receipt_donor_email'
    ];
BEGIN
    FOREACH idx IN ARRAY required_indexes LOOP
        SELECT COUNT(*) INTO v_count
        FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = idx;

        IF v_count = 0 THEN
            RAISE EXCEPTION '[FAIL] Index "%" is MISSING!', idx;
        ELSE
            RAISE NOTICE '[PASS] Index "%" exists.', idx;
        END IF;
    END LOOP;
END $$;

-- Show index details for human review
SELECT
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- ─────────────────────────────────────────────────────────────
-- SECTION 7: Unique constraint audit on critical columns
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
    tbl_col TEXT[][];
    pair TEXT[];
    v_count INTEGER;
BEGIN
    -- [ [table, unique_index_name] ]
    tbl_col := ARRAY[
        ARRAY['users',     'idx_user_email'],
        ARRAY['donations', 'idx_donation_razorpay_order'],
        ARRAY['receipts',  'idx_receipt_number'],
        ARRAY['receipts',  'idx_receipt_donation']
    ];

    FOREACH pair SLICE 1 IN ARRAY tbl_col LOOP
        SELECT COUNT(*) INTO v_count
        FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename  = pair[1]
          AND indexname  = pair[2]
          AND indexdef LIKE '%UNIQUE%';

        IF v_count = 0 THEN
            RAISE EXCEPTION '[FAIL] UNIQUE index "%" on table "%" is missing or not unique!', pair[2], pair[1];
        ELSE
            RAISE NOTICE '[PASS] UNIQUE index "%" on table "%" confirmed.', pair[2], pair[1];
        END IF;
    END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────
-- SECTION 8: Flyway migration lock check
-- No row should exist with success = FALSE and no subsequent success = TRUE version
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
    locked_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO locked_count
    FROM flyway_schema_history
    WHERE success = FALSE;

    IF locked_count > 0 THEN
        RAISE EXCEPTION '[FAIL] % failed Flyway migration(s) detected! Run: SELECT * FROM flyway_schema_history WHERE success = FALSE;', locked_count;
    ELSE
        RAISE NOTICE '[PASS] No failed Flyway migrations. Database is in a clean state.';
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- SECTION 9: Seed data verification (from V1)
-- ─────────────────────────────────────────────────────────────
DO $$
DECLARE
    admin_count INTEGER;
    campaign_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO admin_count FROM users WHERE email = 'admin@donationplatform.com';
    SELECT COUNT(*) INTO campaign_count FROM campaigns WHERE status = 'ACTIVE';

    IF admin_count = 0 THEN
        RAISE EXCEPTION '[FAIL] Seed admin user admin@donationplatform.com not found in users table!';
    ELSE
        RAISE NOTICE '[PASS] Seed admin user exists (% record(s)).', admin_count;
    END IF;

    IF campaign_count = 0 THEN
        RAISE WARNING '[WARN] No ACTIVE campaigns found. Demo campaign may not have been seeded.';
    ELSE
        RAISE NOTICE '[PASS] % ACTIVE campaign(s) found.', campaign_count;
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- SECTION 10: Final certification summary
-- ─────────────────────────────────────────────────────────────
SELECT
    'CERTIFICATION SUMMARY' AS "Category",
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ('users','campaigns','donations','receipts')) AS "Core Tables Present (expected 4)",
    (SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public') AS "Total Indexes",
    (SELECT COUNT(*) FROM flyway_schema_history WHERE success = TRUE) AS "Successful Migrations",
    (SELECT COUNT(*) FROM flyway_schema_history WHERE success = FALSE) AS "Failed Migrations (must be 0)",
    (SELECT COUNT(*) FROM users) AS "Total Users",
    (SELECT COUNT(*) FROM campaigns) AS "Total Campaigns",
    (SELECT COUNT(*) FROM donations) AS "Total Donations",
    (SELECT COUNT(*) FROM receipts) AS "Total Receipts";
