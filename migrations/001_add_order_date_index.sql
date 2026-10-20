-- =========================================================
-- 001_add_order_date_index.sql
-- Purpose:  Add an index on orders.order_date to speed up
--           date range queries, monthly reports and
--           "latest orders" queries.
-- Depends:  000
-- Notes:    Does NOT run in a transaction: CREATE INDEX
--           CONCURRENTLY is not allowed inside BEGIN/COMMIT.
--           Safe to rerun: the index step is skipped if a valid
--           index already exists.
--
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -v ON_ERROR_STOP=1 -f migrations/001_add_order_date_index.sql
-- =========================================================

-- Session-level setting (SET LOCAL only works inside a transaction)
SET lock_timeout = '5s';

-- Pre-check: a failed concurrent build leaves an INVALID index behind.
-- IF NOT EXISTS would silently skip it, so stop and ask to drop it first.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_index
        WHERE indexrelid = to_regclass('public.idx_orders_order_date')
          AND NOT indisvalid
    ) THEN
        RAISE EXCEPTION 'Invalid index idx_orders_order_date found (failed earlier build). '
                        'Run: DROP INDEX CONCURRENTLY idx_orders_order_date; then rerun this migration.';
    END IF;
END $$;

-- Changes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_order_date
    ON orders (order_date);

-- Post-check: the index must exist and be valid
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index
        WHERE indexrelid = to_regclass('public.idx_orders_order_date')
          AND indisvalid
    ) THEN
        RAISE EXCEPTION 'Migration 001 failed: index idx_orders_order_date is missing or invalid';
    END IF;
END $$;

-- Record the migration
INSERT INTO schema_migrations (version, description)
VALUES ('001', 'add index on orders.order_date');
