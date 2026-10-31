-- =========================================================
-- 06_transactions.sql
-- Practice: transactions, savepoints, concurrency, isolation
-- levels, deadlocks and lock monitoring.
--
-- DO NOT run this file with \i or -f. The exercises are meant
-- to be typed (or pasted) statement by statement into
-- interactive psql sessions, watching the results and the
-- prompt after each one:
--     online_shop=>    no transaction open
--     online_shop=*>   transaction open
--     online_shop=!>   transaction aborted by an error
--     online_shop-*>   statement continues on the next line
--     online_shop$*>   inside a $$ ... $$ block
--
-- Open sessions with:
--   psql -U alex_mav -d online_shop
-- Two-session exercises: [A] and [B] mark the session, steps
-- must be done in the numbered order. Exercise 8 also uses [C].
--
-- Requires migration 002 (customers.balance).
-- =========================================================


-- =========================================================
-- RESET: run before starting (or between exercises) to get
-- the starting balances from migration 002 and order 15 back
-- to 'new'.
-- =========================================================
UPDATE customers
SET balance = 50000 + (customer_id % 10) * 10000
WHERE customer_id BETWEEN 2 AND 8;

UPDATE orders SET status = 'new' WHERE order_id = 15;

-- Starting balances: 2 = 70 000, 3 = 80 000, 4 = 90 000,
-- 5 = 100 000, 6 = 110 000, 7 = 120 000, 8 = 130 000.
-- Order 15 (customer 2) has a total of 75 980.
SELECT customer_id, balance FROM customers WHERE customer_id BETWEEN 2 AND 8 ORDER BY customer_id;


-- =========================================================
-- EXERCISE 1. Atomicity: paying for an order
-- Paying = subtract the order total from the balance AND mark
-- the order as paid. Customer 2 has 70 000, too little for 75 980.
-- =========================================================

-- ---- Part A: inside a transaction -----------------------
BEGIN;
UPDATE orders SET status = 'paid' WHERE order_id = 15;
UPDATE customers
SET balance = balance - (SELECT sum(quantity * unit_price) FROM order_items WHERE order_id = 15)
WHERE customer_id = 2;
-- ERROR: violates check constraint "chk_customers_balance_non_negative"
SELECT status FROM orders WHERE order_id = 15;
-- ERROR: current transaction is aborted (even a harmless read is refused)
ROLLBACK;
SELECT status FROM orders WHERE order_id = 15;   -- still 'new': the first update was undone

-- ---- Part B: the same WITHOUT a transaction -------------
UPDATE orders SET status = 'paid' WHERE order_id = 15;   -- committed immediately
UPDATE customers
SET balance = balance - (SELECT sum(quantity * unit_price) FROM order_items WHERE order_id = 15)
WHERE customer_id = 2;                                   -- fails
SELECT o.status, c.balance
FROM orders AS o
JOIN customers AS c ON c.customer_id = o.customer_id
WHERE o.order_id = 15;                                   -- 'paid', balance unchanged: inconsistent!
UPDATE orders SET status = 'new' WHERE order_id = 15;    -- undo by hand

-- ---- Part C: a successful payment -----------------------
UPDATE customers SET balance = balance + 10000 WHERE customer_id = 2;   -- now 80 000

BEGIN;
UPDATE customers                                         -- the step most likely to fail goes first
SET balance = balance - (SELECT sum(quantity * unit_price) FROM order_items WHERE order_id = 15)
WHERE customer_id = 2;
UPDATE orders SET status = 'paid' WHERE order_id = 15;
COMMIT;
-- Result: balance 4 020, order 15 'paid'

-- ---- Part D: guard against paying twice -----------------
-- A transaction makes changes happen together, but it does not check
-- whether they SHOULD happen. Check the business rule inside it.

-- D1: check by hand ("UPDATE 0" means the order is not payable)
BEGIN;
UPDATE orders SET status = 'paid' WHERE order_id = 15 AND status = 'new';
-- UPDATE 0 -> already paid: ROLLBACK here instead of charging again
ROLLBACK;

-- D2: let PostgreSQL stop by itself (FOUND exists only in PL/pgSQL)
BEGIN;
DO $$
BEGIN
    UPDATE orders SET status = 'paid'
    WHERE order_id = 15 AND status = 'new';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order 15 cannot be paid: it does not exist or is not new';
    END IF;
END $$;
-- ERROR from the DO block -> transaction aborted, the charge below is refused
UPDATE customers
SET balance = balance - (SELECT sum(quantity * unit_price) FROM order_items WHERE order_id = 15)
WHERE customer_id = 2;
COMMIT;   -- reported as ROLLBACK


-- =========================================================
-- EXERCISE 2. Savepoints: recover from a failed step
-- ROLLBACK TO SAVEPOINT undoes only the work after the
-- savepoint and makes an aborted transaction usable again.
-- =========================================================
BEGIN;
UPDATE customers SET balance = balance + 1000 WHERE customer_id = 3;
SAVEPOINT before_charge;
UPDATE customers SET balance = balance - 1000000 WHERE customer_id = 2;   -- fails, prompt =!>
ROLLBACK TO SAVEPOINT before_charge;                                       -- prompt back to =*>
UPDATE customers SET balance = balance + 1000 WHERE customer_id = 4;
COMMIT;
SELECT customer_id, balance FROM customers WHERE customer_id IN (2, 3, 4) ORDER BY customer_id;
-- 3 and 4 got +1 000, 2 unchanged.
-- Variation: repeat without the two savepoint lines -> everything is lost.

-- psql helper for experimenting (automatic savepoint before each typed statement):
--   \set ON_ERROR_ROLLBACK interactive


-- =========================================================
-- EXERCISE 3. The lost update (two sessions)
-- A charges 30 000, B charges 20 000 from customer 5 (100 000).
-- Correct result: 50 000.
-- =========================================================

-- ---- Variant 1: read, calculate in the "application", write
-- 1 [A]
BEGIN;
-- 2 [A]
SELECT balance FROM customers WHERE customer_id = 5;          -- 100 000
-- 3 [B]
BEGIN;
-- 4 [B]
SELECT balance FROM customers WHERE customer_id = 5;          -- also 100 000 (readers never wait)
-- 5 [A]
UPDATE customers SET balance = 70000 WHERE customer_id = 5;   -- 100 000 - 30 000
-- 6 [B]  hangs: A holds the row lock
UPDATE customers SET balance = 80000 WHERE customer_id = 5;   -- 100 000 - 20 000
-- 7 [A]  B's update now completes
COMMIT;
-- 8 [B]
COMMIT;
-- 9 [A]
SELECT balance FROM customers WHERE customer_id = 5;          -- 80 000: A's charge is LOST

-- reset
UPDATE customers SET balance = 100000 WHERE customer_id = 5;

-- ---- Variant 2 (fix 1): let the database calculate -------
-- Same steps, but in steps 5 and 6:
--   5 [A]  UPDATE customers SET balance = balance - 30000 WHERE customer_id = 5;
--   6 [B]  UPDATE customers SET balance = balance - 20000 WHERE customer_id = 5;   (waits)
-- After A commits, B re-reads the newest version (70 000) -> result 50 000.

-- ---- Variant 3 (fix 2): lock the row when reading --------
-- reset to 100 000, then:
-- 1 [A]
BEGIN;
-- 2 [A]
SELECT balance FROM customers WHERE customer_id = 5 FOR UPDATE;   -- 100 000, row locked
-- 3 [B]
BEGIN;
-- 4 [B]  waits already here
SELECT balance FROM customers WHERE customer_id = 5 FOR UPDATE;
-- 5 [A]
UPDATE customers SET balance = 70000 WHERE customer_id = 5;
-- 6 [A]  B's SELECT now returns 70 000
COMMIT;
-- 7 [B]
UPDATE customers SET balance = 50000 WHERE customer_id = 5;       -- 70 000 - 20 000
-- 8 [B]
COMMIT;                                                            -- result 50 000

-- Watching the row versions (system columns):
--   [A] after its UPDATE:  SELECT pg_current_xact_id();
--   [B] before updating:   SELECT xmin, xmax, ctid, balance FROM customers WHERE customer_id = 5;
--       (old version, xmax = A's transaction ID)


-- =========================================================
-- EXERCISE 4. Non-repeatable read (two sessions)
-- Read Committed: each STATEMENT sees a fresh snapshot.
-- Repeatable Read: the whole TRANSACTION sees one snapshot,
-- taken at its first statement.
-- =========================================================

-- ---- Read Committed (default) ---------------------------
-- 1 [A]
BEGIN;
-- 2 [A]
SELECT balance FROM customers WHERE customer_id = 6;
-- 3 [B]
UPDATE customers SET balance = balance + 5000 WHERE customer_id = 6;   -- autocommits
-- 4 [A]
SELECT balance FROM customers WHERE customer_id = 6;   -- +5 000: same query, different result
-- 5 [A]
COMMIT;

-- ---- Repeatable Read -----------------------------------
-- 1 [A]
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- 2 [A]
SELECT balance FROM customers WHERE customer_id = 6;
-- 3 [B]
UPDATE customers SET balance = balance + 5000 WHERE customer_id = 6;
-- 4 [A]
SELECT balance FROM customers WHERE customer_id = 6;   -- unchanged: A's snapshot
-- 5 [A]
COMMIT;
SELECT balance FROM customers WHERE customer_id = 6;   -- now shows B's change


-- =========================================================
-- EXERCISE 5. Serialization error on write (two sessions)
-- At Repeatable Read, reads never conflict, but writing a row
-- changed after the snapshot does.
-- =========================================================
-- 1 [A]
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- 2 [A]
SELECT balance FROM customers WHERE customer_id = 6;
-- 3 [B]
UPDATE customers SET balance = balance + 1000 WHERE customer_id = 6;   -- autocommits
-- 4 [A]
UPDATE customers SET balance = balance - 1000 WHERE customer_id = 6;
-- ERROR: could not serialize access due to concurrent update
-- 5 [A]  the correct reaction: retry the whole transaction
ROLLBACK;


-- =========================================================
-- EXERCISE 6. Write skew (two sessions)
-- Rule: customers 7 and 8 together must keep at least 200 000.
-- Each session checks the rule and withdraws 40 000 from a
-- DIFFERENT customer. Reset 7 and 8 before each run!
-- =========================================================
UPDATE customers SET balance = 120000 WHERE customer_id = 7;
UPDATE customers SET balance = 130000 WHERE customer_id = 8;

-- ---- Repeatable Read: the anomaly slips through ---------
-- 1 [A]
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- 2 [A]
SELECT sum(balance) FROM customers WHERE customer_id IN (7, 8);   -- 250 000: withdrawal allowed
-- 3 [B]
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- 4 [B]
SELECT sum(balance) FROM customers WHERE customer_id IN (7, 8);   -- 250 000: allowed too
-- 5 [A]
UPDATE customers SET balance = balance - 40000 WHERE customer_id = 7;
-- 6 [B]  no waiting: a different row
UPDATE customers SET balance = balance - 40000 WHERE customer_id = 8;
-- 7 [A]
COMMIT;
-- 8 [B]
COMMIT;
SELECT sum(balance) FROM customers WHERE customer_id IN (7, 8);   -- 170 000: rule broken

-- ---- Serializable: one transaction is aborted -----------
-- reset 7 and 8, then repeat with in both sessions:
--   BEGIN ISOLATION LEVEL SERIALIZABLE;
-- One of them fails (typically at COMMIT) with:
--   could not serialize access due to read/write dependencies among transactions
-- A retry would see the new sum (210 000) and refuse the withdrawal.
-- Note: the rule is only "in our heads". To really enforce it, each
-- transaction must check it, e.g. in a DO block with RAISE EXCEPTION.


-- =========================================================
-- EXERCISE 7. Deadlock (two sessions)
-- A transfers 3 -> 4, B transfers 4 -> 3, locking rows in
-- opposite order.
-- =========================================================
-- 1 [A]
BEGIN;
-- 2 [A]
UPDATE customers SET balance = balance - 1000 WHERE customer_id = 3;   -- locks row 3
-- 3 [B]
BEGIN;
-- 4 [B]
UPDATE customers SET balance = balance - 1000 WHERE customer_id = 4;   -- locks row 4
-- 5 [A]  waits for B
UPDATE customers SET balance = balance + 1000 WHERE customer_id = 4;
-- 6 [B]  waits for A -> deadlock, one session fails after ~1 s (deadlock_timeout)
UPDATE customers SET balance = balance + 1000 WHERE customer_id = 3;
-- ERROR: deadlock detected
-- 7 [A] and [B]
COMMIT;   -- the survivor commits, the victim's COMMIT becomes ROLLBACK

-- ---- Fix: always lock rows in the same order (lower ID first)
-- Both sessions touch customer 3 first, whatever the direction:
--   [A] 3 -> 4:  UPDATE ... - 1000 WHERE customer_id = 3;  UPDATE ... + 1000 WHERE customer_id = 4;
--   [B] 4 -> 3:  UPDATE ... + 1000 WHERE customer_id = 3;  UPDATE ... - 1000 WHERE customer_id = 4;
-- B waits at its FIRST update, holding nothing -> no cycle, both succeed.

-- Alternative: lock all needed rows at the start, in a fixed order
BEGIN;
SELECT customer_id FROM customers
WHERE customer_id IN (3, 4)
ORDER BY customer_id
FOR UPDATE;
UPDATE customers SET balance = balance + 1000 WHERE customer_id = 3;
UPDATE customers SET balance = balance - 1000 WHERE customer_id = 4;
COMMIT;


-- =========================================================
-- EXERCISE 8. Watching and resolving a blockage
-- (three sessions: A blocks, B waits, C monitors)
-- =========================================================
-- 1 [A]  open a transaction, change a row, then do nothing
BEGIN;
UPDATE customers SET balance = balance + 1 WHERE customer_id = 6;

-- 2 [B]  hangs
UPDATE customers SET balance = balance + 1 WHERE customer_id = 6;

-- 3 [C]  who is doing what, and who blocks whom?
SELECT pid, state, wait_event_type, wait_event,
       now() - xact_start    AS transaction_age,
       pg_blocking_pids(pid) AS blocked_by,
       left(query, 60)       AS last_query
FROM pg_stat_activity
WHERE datname = 'online_shop'
ORDER BY pid;
-- A: 'idle in transaction'; B: active, waiting on Lock / transactionid,
-- blocked_by = A's pid

-- 4 [C]  the locks themselves (granted = false is the waiting request)
SELECT pid, locktype, relation::regclass AS table_name, transactionid, mode, granted
FROM pg_locks
WHERE pid IN (SELECT pid FROM pg_stat_activity WHERE datname = 'online_shop')
ORDER BY pid, granted DESC;

-- 5 [C]  cancel B's waiting query (B stays connected)
--   SELECT pg_cancel_backend(<B's pid>);
-- 6 [B]  rerun the UPDATE so it waits again
-- 7 [C]  terminate the blocker: A's transaction is rolled back, B continues
--   SELECT pg_terminate_backend(<A's pid>);

-- Safety net against forgotten transactions (per session, role or database):
--   SET idle_in_transaction_session_timeout = '5min';
--   ALTER ROLE alex_mav SET idle_in_transaction_session_timeout = '5min';   (as postgres)


-- =========================================================
-- Summary of lessons
-- =========================================================
-- 1. Group changes that belong together in one transaction; after an
--    error the whole transaction is aborted (COMMIT becomes ROLLBACK).
-- 2. Check business rules inside the transaction ("UPDATE 0" is not an
--    error); FOUND + RAISE EXCEPTION makes PostgreSQL stop by itself.
-- 3. Savepoints undo part of a transaction and recover from errors.
-- 4. Never calculate new values from a value read earlier without
--    locking: use balance = balance - x, or SELECT ... FOR UPDATE.
-- 5. Read Committed: fresh data per statement. Repeatable Read: one
--    snapshot, serialization errors on conflicting writes. Serializable:
--    also prevents write skew. Writers at higher levels need retries.
-- 6. Lock rows in a consistent order to avoid deadlocks; be ready to
--    retry when one happens (error code 40P01).
-- 7. Keep transactions short; watch pg_stat_activity for
--    'idle in transaction' sessions and pg_blocking_pids() for blockers.
