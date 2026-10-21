-- =========================================================
-- 05_index_benchmarks.sql
-- Measures the effect of two indexes added by migrations:
--   idx_orders_order_date      (migration 001)
--   uq_customers_email_lower   (migration 003)
-- by running the same queries with and without each index.
--
-- Requirements:
--   - seed/02_generated_data.sql loaded (enough rows to matter)
--   - migrations 001 and 003 applied
--
-- The database is NOT changed: every test that removes an index
-- does it inside BEGIN ... ROLLBACK, and the helper function
-- lives in pg_temp, so it disappears when the session ends.
-- Note: DROP INDEX locks the table until ROLLBACK, so run this
-- only on your own database, not a shared one.
--
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -f queries/05_index_benchmarks.sql
-- =========================================================

-- Fresh statistics, so the planner sees the real table sizes
ANALYZE orders;
ANALYZE customers;


-- ---------------------------------------------------------
-- Helper: run a query many times and report the average time.
-- Created in pg_temp (temporary schema): visible only in this
-- session and dropped automatically when the session ends.
-- ---------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.bench(label TEXT, query TEXT, runs INTEGER DEFAULT 200)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    started TIMESTAMPTZ;
    elapsed INTERVAL;
BEGIN
    EXECUTE query;                          -- warm-up run (loads pages into memory)

    started := clock_timestamp();           -- real time, changes during a transaction
    FOR i IN 1..runs LOOP
        EXECUTE query;                      -- result rows are discarded
    END LOOP;
    elapsed := clock_timestamp() - started;

    RAISE NOTICE '%  %  ms per run  (% runs)',
        rpad(label, 50),
        lpad(round((EXTRACT(EPOCH FROM elapsed) * 1000 / runs)::numeric, 3)::text, 9),
        runs;
END
$$;


-- =========================================================
-- PART 1. Execution plans: what changes without the index
-- Compare the plan type (Index Scan / Bitmap / Seq Scan),
-- "Buffers" (pages read) and "Execution Time".
-- =========================================================

\echo
\echo '=== 1.1 One month of orders: WITH idx_orders_order_date ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE order_date >= '2026-05-01 00:00+05'
  AND order_date <  '2026-06-01 00:00+05';

\echo '=== 1.1 One month of orders: WITHOUT the index ==='
BEGIN;
DROP INDEX idx_orders_order_date;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE order_date >= '2026-05-01 00:00+05'
  AND order_date <  '2026-06-01 00:00+05';
ROLLBACK;

\echo
\echo '=== 1.2 Ten latest orders: WITH idx_orders_order_date ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
ORDER BY order_date DESC
LIMIT 10;

\echo '=== 1.2 Ten latest orders: WITHOUT the index ==='
BEGIN;
DROP INDEX idx_orders_order_date;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
ORDER BY order_date DESC
LIMIT 10;
ROLLBACK;

\echo
\echo '=== 1.3 Case-insensitive email lookup: WITH uq_customers_email_lower ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM customers
WHERE lower(email) = lower('Customer500@Example.com');

\echo '=== 1.3 Case-insensitive email lookup: WITHOUT the index ==='
BEGIN;
DROP INDEX uq_customers_email_lower;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM customers
WHERE lower(email) = lower('Customer500@Example.com');
ROLLBACK;

\echo
\echo '=== 1.4 Exact email lookup (no lower): cannot use the lower(email) index ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM customers
WHERE email = 'customer500@example.com';


-- =========================================================
-- PART 2. Average time over many runs (more reliable than a
-- single EXPLAIN ANALYZE). Each measurement includes planning,
-- because EXECUTE plans the query every time.
-- =========================================================

\echo
\echo '=== 2. Average execution time (200 runs each) ==='

SELECT pg_temp.bench('order_date one month    | with index',
    $q$SELECT * FROM orders
       WHERE order_date >= '2026-05-01 00:00+05'
         AND order_date <  '2026-06-01 00:00+05'$q$);

SELECT pg_temp.bench('order_date latest 10    | with index',
    $q$SELECT * FROM orders ORDER BY order_date DESC LIMIT 10$q$);

SELECT pg_temp.bench('lower(email) lookup     | with index',
    $q$SELECT * FROM customers
       WHERE lower(email) = lower('Customer500@Example.com')$q$);

BEGIN;
DROP INDEX idx_orders_order_date;

SELECT pg_temp.bench('order_date one month    | WITHOUT index',
    $q$SELECT * FROM orders
       WHERE order_date >= '2026-05-01 00:00+05'
         AND order_date <  '2026-06-01 00:00+05'$q$);

SELECT pg_temp.bench('order_date latest 10    | WITHOUT index',
    $q$SELECT * FROM orders ORDER BY order_date DESC LIMIT 10$q$);
ROLLBACK;

BEGIN;
DROP INDEX uq_customers_email_lower;

SELECT pg_temp.bench('lower(email) lookup     | WITHOUT index',
    $q$SELECT * FROM customers
       WHERE lower(email) = lower('Customer500@Example.com')$q$);
ROLLBACK;


-- =========================================================
-- PART 3. The cost of indexes on writes: insert 5 000 orders
-- with all orders indexes, then without the two non-key
-- indexes. Both inserts are rolled back.
-- =========================================================

\echo
\echo '=== 3. Inserting 5 000 orders ==='

BEGIN;
DO $$
DECLARE
    started TIMESTAMPTZ := clock_timestamp();
BEGIN
    INSERT INTO orders (customer_id, order_date, status, shipping_address)
    SELECT 1, timestamptz '2026-01-01 00:00+05' + g * interval '1 minute', 'delivered', 'Test address'
    FROM generate_series(1, 5000) AS g;

    RAISE NOTICE '%  %  ms',
        rpad('insert 5 000 orders      | with indexes', 50),
        lpad(round((EXTRACT(EPOCH FROM clock_timestamp() - started) * 1000)::numeric, 1)::text, 9);
END
$$;
ROLLBACK;

BEGIN;
DROP INDEX idx_orders_order_date;
DROP INDEX idx_orders_customer_id;
DO $$
DECLARE
    started TIMESTAMPTZ := clock_timestamp();
BEGIN
    INSERT INTO orders (customer_id, order_date, status, shipping_address)
    SELECT 1, timestamptz '2026-01-01 00:00+05' + g * interval '1 minute', 'delivered', 'Test address'
    FROM generate_series(1, 5000) AS g;

    RAISE NOTICE '%  %  ms',
        rpad('insert 5 000 orders      | WITHOUT 2 indexes', 50),
        lpad(round((EXTRACT(EPOCH FROM clock_timestamp() - started) * 1000)::numeric, 1)::text, 9);
END
$$;
ROLLBACK;

\echo
\echo 'Done. Nothing was changed: all index drops and inserts were rolled back.'
