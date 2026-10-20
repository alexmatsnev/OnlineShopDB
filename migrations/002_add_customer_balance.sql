-- =========================================================
-- 002_add_customer_balance.sql
-- Purpose:  Add a balance column to customers and
--           give existing customers a starting balance,
--           for practicing transactions and isolation levels.
-- Depends:  baseline schema and migration 000
-- Notes:    Runs in a single transaction. Reversible by
--           dropping the column (data in it would be lost).
--
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -v ON_ERROR_STOP=1 -f migrations/002_add_customer_balance.sql
-- =========================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- Pre-check: nothing to verify (new column)

-- Changes
ALTER TABLE customers
    ADD COLUMN balance NUMERIC(12, 2) NOT NULL DEFAULT 0
    CONSTRAINT chk_customers_balance_non_negative CHECK (balance >= 0);
    
-- Give existing customers a starting balance (deterministic, for practice)
UPDATE customers
SET balance = 50000 + (customer_id % 10) * 10000;

-- Post-check: every customer must have received a starting balance
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM customers WHERE balance = 0) THEN
        RAISE EXCEPTION 'Migration 002 failed: customers without starting balance found';
    END IF;
END $$;

-- Record the migration
INSERT INTO schema_migrations (version, description)
VALUES ('002', 'add customer balance');

COMMIT;