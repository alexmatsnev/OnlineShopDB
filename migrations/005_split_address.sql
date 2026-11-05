-- =========================================================
-- 005_split_address.sql
-- Purpose:  Split customers.address into two new columns,
--           city and street (expand step of expand/contract).
--           The address column is kept unchanged.
-- Depends:  baseline schema and migration 000
-- Notes:    Runs in a single transaction. Reversible by dropping
--           the new columns, as long as address still exists.
--           Until migration 009, inserts and seed scripts fill
--           only address; city and street stay empty for new rows.
--
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -v ON_ERROR_STOP=1 -f migrations/005_split_address.sql
-- =========================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- Pre-check: every address must be "City, Street": exactly one comma,
-- with a non-empty part on each side
DO $$
DECLARE
    bad_ids TEXT;
BEGIN
    SELECT string_agg(customer_id::text, ', ' ORDER BY customer_id)
    INTO bad_ids
    FROM customers
    WHERE address IS NOT NULL
      AND (length(address) - length(replace(address, ',', '')) <> 1
           OR trim(split_part(address, ',', 1)) = ''
           OR trim(split_part(address, ',', 2)) = '');

    IF bad_ids IS NOT NULL THEN
        RAISE EXCEPTION 'Migration 005 failed: addresses cannot be split for customers %', bad_ids
            USING HINT = 'Each address must contain exactly one comma separating a non-empty city and street.';
    END IF;
END $$;

-- Changes: new columns
ALTER TABLE customers
    ADD COLUMN city   VARCHAR(100),
    ADD COLUMN street TEXT;

-- Fill them from address (customers without an address keep NULLs)
UPDATE customers
SET city   = nullif(trim(split_part(address, ',', 1)), ''),
    street = nullif(trim(split_part(address, ',', 2)), '')
WHERE address IS NOT NULL;

-- Post-check: the split is lossless, city + ', ' + street = address
DO $$
DECLARE
    bad_ids TEXT;
BEGIN
    SELECT string_agg(customer_id::text, ', ' ORDER BY customer_id)
    INTO bad_ids
    FROM customers
    WHERE (city || ', ' || street) IS DISTINCT FROM address;

    IF bad_ids IS NOT NULL THEN
        RAISE EXCEPTION 'Migration 005 failed: split is not lossless for customers %', bad_ids;
    END IF;
END $$;

-- Record the migration
INSERT INTO schema_migrations (version, description)
VALUES ('005', 'split customers.address into city and street');

COMMIT;