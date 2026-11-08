-- =========================================================
-- 009_add_balance_ledger.sql
-- Purpose:  Create the balance_transactions ledger, add one
--           'opening' row per customer with a non-zero balance,
--           and replace pay_order so every payment also writes
--           a ledger row.
-- Depends:  Baseline schema and migrations 000, 002, 004.
-- Notes:    Runs in a single transaction.
--           Invariant: each customer's balance equals the sum of
--           their ledger rows (checked at the end).
--           Payments made before this migration aren't reconstructed:
--           the opening row stands for all of them.
--           Ledger rows should never be updated or deleted: a mistake
--           is corrected with a new row, like a refund.
--           From now on, every balance change must also insert a
--           ledger row (pay_order does; manual UPDATEs don't).
--           Reversible by restoring the previous pay_order FIRST
--           (PL/pgSQL bodies are not dependency-checked), then
--           dropping balance_transactions.
--
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -v ON_ERROR_STOP=1 -f migrations/009_add_balance_ledger.sql
-- =========================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- Block writes to customers until COMMIT, so no balance can change
-- between the opening rows and the invariant check
LOCK TABLE customers IN SHARE ROW EXCLUSIVE MODE;

-- Pre-check: nothing to verify

-- Changes:
-- Create the ledger table
CREATE TABLE balance_transactions (
    transaction_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id     INTEGER        NOT NULL REFERENCES customers (customer_id),
    amount          NUMERIC(12, 2) NOT NULL,
    type            VARCHAR(20)    NOT NULL
                    CONSTRAINT chk_balance_transactions_type
                    CHECK (type IN ('opening', 'deposit', 'payment', 'refund',
                                    'transfer_in', 'transfer_out')),
    order_id        INTEGER        REFERENCES orders (order_id),
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT now(),

    -- Payments and refunds always reference an order; other types never do
    CONSTRAINT chk_balance_transactions_order_ref
        CHECK ((type IN ('payment', 'refund')) = (order_id IS NOT NULL)),

    -- The sign of the amount must match the type (this also rules out 0)
    CONSTRAINT chk_balance_transactions_amount_sign
        CHECK ((type IN ('opening', 'deposit', 'refund', 'transfer_in') AND amount > 0)
            OR (type IN ('payment', 'transfer_out')                   AND amount < 0))
);

-- A customer's transactions in date order (also serves the customer_id foreign key)
CREATE INDEX idx_balance_transactions_customer_id_date
    ON balance_transactions (customer_id, created_at);

-- Foreign key on order_id; only payments and refunds have one
CREATE INDEX idx_balance_transactions_order_id
    ON balance_transactions (order_id)
    WHERE order_id IS NOT NULL;

-- Opening rows: one per customer with a non-zero balance
-- (a zero balance needs no row: the sum of no rows is 0)
INSERT INTO balance_transactions (customer_id, amount, type)
SELECT customer_id, balance, 'opening'
FROM customers
WHERE balance <> 0;

-- Replace pay_order: same signature, plus a ledger row per payment
CREATE OR REPLACE PROCEDURE pay_order(
    p_order_id  INTEGER,
    INOUT new_balance NUMERIC DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id  orders.customer_id%TYPE;
    v_status       orders.status%TYPE;
    v_total        customers.balance%TYPE;
    v_balance      customers.balance%TYPE;
BEGIN
    -- 1. Lock the order first (always order -> customer, to avoid deadlocks)
    SELECT customer_id, status
    INTO v_customer_id, v_status
    FROM orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % does not exist', p_order_id
            USING ERRCODE = 'no_data_found';
    END IF;

    IF v_status <> 'new' THEN
        RAISE EXCEPTION 'Order % cannot be paid: its status is %', p_order_id, v_status
            USING HINT = 'Only orders with status ''new'' can be paid.';
    END IF;

    -- 2. Order total
    SELECT sum(quantity * unit_price)
    INTO v_total
    FROM order_items
    WHERE order_id = p_order_id;

    IF v_total IS NULL THEN
        RAISE EXCEPTION 'Order % has no items', p_order_id;
    END IF;

    -- 3. Lock the customer and check the balance
    SELECT balance
    INTO v_balance
    FROM customers
    WHERE customer_id = v_customer_id
    FOR UPDATE;

    IF v_balance < v_total THEN
        RAISE EXCEPTION 'Insufficient balance to pay order %', p_order_id
            USING DETAIL = format('Order total: %s, balance of customer %s: %s',
                                  v_total, v_customer_id, v_balance),
                  HINT   = 'Top up the balance and try again.';
    END IF;

    -- 4. Ledger row, while order and customer are locked
    INSERT INTO balance_transactions (customer_id, amount, type, order_id)
    VALUES (v_customer_id, -v_total, 'payment', p_order_id);

    -- 5. Charge and mark as paid
    UPDATE customers
    SET balance = balance - v_total
    WHERE customer_id = v_customer_id
    RETURNING balance INTO new_balance;

    UPDATE orders
    SET status = 'paid'
    WHERE order_id = p_order_id;
END;
$$;

-- Post-check: the invariant, every balance equals the sum of its ledger rows
DO $$
DECLARE
    bad_ids TEXT;
BEGIN
    SELECT string_agg(c.customer_id::text, ', ' ORDER BY c.customer_id)
    INTO bad_ids
    FROM customers AS c
    LEFT JOIN (
        SELECT customer_id, sum(amount) AS ledger_sum
        FROM balance_transactions
        GROUP BY customer_id
    ) AS bt ON bt.customer_id = c.customer_id
    WHERE c.balance <> COALESCE(bt.ledger_sum, 0);

    IF bad_ids IS NOT NULL THEN
        RAISE EXCEPTION 'Migration 009 failed: balance does not match ledger for customers %', bad_ids;
    END IF;
END $$;

-- Record the migration
INSERT INTO schema_migrations (version, description)
VALUES ('009', 'add balance ledger and record payments in pay_order');

COMMIT;
