-- =========================================================
-- 006_one_new_order_per_customer.sql
-- Purpose:  Create a unique partial index on orders.customer_id with
--           orders.status = 'new' in order to enforce the
--           "one new order per customer" rule.
-- Depends:  Baseline schema and migration 000
-- Notes:    Runs in a single transaction. Reversible by dropping
--           the new index, but the data change will remain permanent.
--           For customers with several new orders the oldest one
--           (ties broken by order_id) stays in status 'new' and the
--           other ones are changed to 'cancelled'. The IDs of the
--           cancelled orders are printed as a NOTICE.
--
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -v ON_ERROR_STOP=1 -f migrations/006_one_new_order_per_customer.sql
-- =========================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- Optional on a shared database: block other writers on orders until
-- COMMIT, so no new duplicate can appear between the cleanup and the index.
LOCK TABLE orders IN SHARE ROW EXCLUSIVE MODE;

-- Pre-check: nothing to verify

-- Changes:
-- change status to 'cancelled' for new orders that came after the
-- customer's first new order
DO $$
DECLARE
    cancelled_ids TEXT;
BEGIN
    WITH numbered AS (
        SELECT order_id,
               row_number() OVER (PARTITION BY customer_id
                                  ORDER BY order_date, order_id) AS row_num
        FROM orders
        WHERE status = 'new'
    ),
    cancelled AS (
        UPDATE orders
        SET status = 'cancelled'
        WHERE order_id IN (SELECT order_id FROM numbered WHERE row_num > 1)
        RETURNING order_id
    )
    SELECT string_agg(order_id::text, ', ' ORDER BY order_id)
    INTO cancelled_ids
    FROM cancelled;

    IF cancelled_ids IS NOT NULL THEN
        RAISE NOTICE 'Orders changed from new to cancelled: %', cancelled_ids;
    ELSE
        RAISE NOTICE 'No duplicate new orders found, nothing cancelled';
    END IF;
END $$;

-- new unique partial index
CREATE UNIQUE INDEX uq_one_new_order_per_customer
ON orders (customer_id)
WHERE status = 'new';

-- Post-check: nothing to verify (the unique index creation would fail
-- if duplicates remained)

-- Record the migration
INSERT INTO schema_migrations (version, description)
VALUES ('006', 'one new order per customer rule');

COMMIT;
