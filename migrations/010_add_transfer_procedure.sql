-- =========================================================
-- 010_add_transfer_procedure.sql
-- Purpose:  Add a transfer_balance procedure that moves an amount
--           from one customer's balance to another's, with a
--           sufficient-balance check and protection against
--           concurrent transfers, writing both ledger rows.
-- Depends:  Migrations 000, 002, 009 (balance_transactions)
-- Notes:    Runs in a single transaction. The procedure does not
--           COMMIT, so callers can group calls in one transaction.
--           Concurrency: both customers are locked FOR UPDATE in
--           customer_id order before the balance is read, so a
--           parallel transfer from the same customer waits and then
--           sees the reduced balance, and opposite transfers cannot
--           deadlock each other.
--           Not covered: the SAME request submitted twice (e.g. a
--           client retry) is executed twice if the balance allows;
--           preventing that needs an idempotency key.
--
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -v ON_ERROR_STOP=1 -f migrations/010_add_transfer_procedure.sql
-- =========================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- Pre-check: nothing to verify (new procedure)

-- Changes
CREATE PROCEDURE transfer_balance(
    p_from_customer_id  INTEGER,
    p_to_customer_id    INTEGER,
    p_amount            NUMERIC,
    INOUT from_balance  NUMERIC DEFAULT NULL,
    INOUT to_balance    NUMERIC DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_locked_count  INTEGER;
    v_balance       customers.balance%TYPE;
BEGIN
    -- 1. Validate the arguments
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer amount must be positive, got %', p_amount;
    END IF;

    IF p_amount <> round(p_amount, 2) THEN
        RAISE EXCEPTION 'Transfer amount % has more than two decimal places', p_amount;
    END IF;

    IF p_from_customer_id = p_to_customer_id THEN
        RAISE EXCEPTION 'Cannot transfer from customer % to the same customer', p_from_customer_id;
    END IF;

    -- 2. Lock BOTH customers in customer_id order (prevents deadlocks
    --    between opposite transfers) and check that both exist
    PERFORM 1
    FROM customers
    WHERE customer_id IN (p_from_customer_id, p_to_customer_id)
    ORDER BY customer_id
    FOR UPDATE;

    GET DIAGNOSTICS v_locked_count = ROW_COUNT;

    IF v_locked_count <> 2 THEN
        RAISE EXCEPTION 'Customer % or customer % does not exist',
                        p_from_customer_id, p_to_customer_id
            USING ERRCODE = 'no_data_found';
    END IF;

    -- 3. Check the source balance (read AFTER locking: it is current
    --    and cannot change until this transaction ends)
    SELECT balance
    INTO v_balance
    FROM customers
    WHERE customer_id = p_from_customer_id;

    IF v_balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient balance for transfer from customer %', p_from_customer_id
            USING DETAIL = format('Transfer amount: %s, balance: %s', p_amount, v_balance),
                  HINT   = 'Top up the balance or transfer a smaller amount.';
    END IF;

    -- 4. Ledger rows for both sides
    INSERT INTO balance_transactions (customer_id, amount, type)
    VALUES (p_from_customer_id, -p_amount, 'transfer_out'),
           (p_to_customer_id,    p_amount, 'transfer_in');

    -- 5. Update both balances
    UPDATE customers
    SET balance = balance - p_amount
    WHERE customer_id = p_from_customer_id
    RETURNING balance INTO from_balance;

    UPDATE customers
    SET balance = balance + p_amount
    WHERE customer_id = p_to_customer_id
    RETURNING balance INTO to_balance;
END;
$$;

-- Post-check: nothing to verify (creating a procedure changes no data)

-- Record the migration
INSERT INTO schema_migrations (version, description)
VALUES ('010', 'add transfer_balance procedure');

COMMIT;
