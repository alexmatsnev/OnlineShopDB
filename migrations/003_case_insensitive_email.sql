-- =========================================================
-- 003_case_insensitive_email.sql
-- Purpose:  Make customer emails unique regardless of letter case,
--           by replacing the unique constraint on email with a
--           unique index on lower(email).
-- Depends:  baseline schema and migration 000
-- Notes:    Runs in a single transaction. Exact-match lookups
--           should use lower(email) = lower('...') afterwards.
--
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -v ON_ERROR_STOP=1 -f migrations/003_case_insensitive_email.sql
-- =========================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- Pre-check: no emails that differ only in letter case
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM customers
        GROUP BY lower(email)
        HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Migration 003 failed: emails differing only in case exist; clean them up first';
    END IF;
END $$;

-- Changes
CREATE UNIQUE INDEX uq_customers_email_lower
    ON customers (lower(email));

-- The old exact-match unique constraint is now redundant
ALTER TABLE customers DROP CONSTRAINT customers_email_key;

-- Post-check: nothing to verify (errors above abort the transaction)

-- Record the migration
INSERT INTO schema_migrations (version, description)
VALUES ('003', 'case-insensitive unique email via unique index on lower(email)');

COMMIT;