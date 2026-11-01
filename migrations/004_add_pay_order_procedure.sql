-- =========================================================
-- 004_add_pay_order_procedure.sql
-- Purpose:  Add a pay_order procedure that pays a 'new' order
--           from the customer's balance safely: checks that the
--           order exists, is payable and has items, checks the
--           balance, then charges and marks the order as paid,
--           all or nothing.
-- Depends:  000, 002 (customers.balance)
-- Notes:    Runs in a single transaction. The procedure itself
--           does not COMMIT, so callers can group several calls
--           in one transaction.
--
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -v ON_ERROR_STOP=1 -f migrations/004_add_pay_order_procedure.sql
-- =========================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- Pre-check: nothing to verify (new procedure)

-- Changes
CREATE PROCEDURE pay_order(
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

    -- 4. Charge and mark as paid
    UPDATE customers
    SET balance = balance - v_total
    WHERE customer_id = v_customer_id
    RETURNING balance INTO new_balance;

    UPDATE orders
    SET status = 'paid'
    WHERE order_id = p_order_id;
END;
$$;

-- Post-check: nothing to verify (errors above abort the transaction)

-- Record the migration
INSERT INTO schema_migrations (version, description)
VALUES ('004', 'add pay_order procedure');

COMMIT;
