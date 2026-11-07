-- =========================================================
-- 008_fix_usb_hub_category.sql
-- Purpose:  Correct missing category for USB hub products.
-- Depends:  Migration 007.
-- Notes:    Runs in a single transaction.
-- 
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -v ON_ERROR_STOP=1 -f migrations/008_fix_usb_hub_category.sql
-- =========================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- Pre-check: nothing to verify

-- Changes
UPDATE products AS p
SET category_id = c.category_id
FROM categories AS c
WHERE c.name = 'USB hubs'
  AND p.name ILIKE '%hub%'
  AND p.category_id IS NULL;

-- Post-check: no products without a category
DO $$
DECLARE
    missing TEXT;
BEGIN
    SELECT string_agg(product_id::text, ', ' ORDER BY product_id)
    INTO missing
    FROM products
    WHERE category_id IS NULL;

    IF missing IS NOT NULL THEN
        RAISE EXCEPTION 'Migration 008 failed: products still without category: %', missing;
    END IF;
END $$;

-- Post-check: nothing to verify

INSERT INTO schema_migrations (version, description)
VALUES ('008', 'assign USB hub products to USB hubs category');

COMMIT;
