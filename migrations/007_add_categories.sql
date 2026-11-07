-- =========================================================
-- 007_add_categories.sql
-- Purpose:  Create a categories table (two-level tree via parent_id),
--           add products.category_id, and assign existing products
--           to categories by name patterns.
-- Depends:  Baseline schema and migration 000
-- Notes:    Runs in a single transaction. Reversible by dropping
--           products.category_id, then the categories table.
--           Products inserted later (e.g. by seed scripts) get no
--           category until assigned.
--
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -v ON_ERROR_STOP=1 -f migrations/007_add_categories.sql
-- =========================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- Pre-check: nothing to verify

-- Changes
-- Create categories table (top-level categories have parent_id NULL)
CREATE TABLE categories (
    category_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_id    INTEGER REFERENCES categories (category_id),
    name         VARCHAR(50) NOT NULL,
    CONSTRAINT chk_categories_not_own_parent CHECK (parent_id <> category_id)
);

-- Case-insensitive unique category name
CREATE UNIQUE INDEX uq_categories_name_lower ON categories (lower(name));

-- Add category_id to products
ALTER TABLE products
    ADD COLUMN category_id INTEGER REFERENCES categories (category_id) ON DELETE SET NULL;

-- Find all products of a category; join products with categories
CREATE INDEX idx_products_category_id ON products (category_id);

-- Insert parent categories
INSERT INTO categories (parent_id, name) VALUES
    (NULL, 'laptops'),
    (NULL, 'monitors'),
    (NULL, 'input devices'),
    (NULL, 'headset'),
    (NULL, 'storage devices'),
    (NULL, 'accessories');

-- Insert child categories (parents looked up by name, never by ID)
INSERT INTO categories (parent_id, name) VALUES
    ((SELECT category_id FROM categories WHERE name = 'input devices'),   'mice'),
    ((SELECT category_id FROM categories WHERE name = 'input devices'),   'keyboards'),
    ((SELECT category_id FROM categories WHERE name = 'input devices'),   'mouse pads'),
    ((SELECT category_id FROM categories WHERE name = 'headset'),         'headphones'),
    ((SELECT category_id FROM categories WHERE name = 'headset'),         'speakers'),
    ((SELECT category_id FROM categories WHERE name = 'headset'),         'webcams'),
    ((SELECT category_id FROM categories WHERE name = 'storage devices'), 'SSDs'),
    ((SELECT category_id FROM categories WHERE name = 'accessories'),     'cables'),
    ((SELECT category_id FROM categories WHERE name = 'accessories'),     'chargers'),
    ((SELECT category_id FROM categories WHERE name = 'accessories'),     'laptop stands'),
    ((SELECT category_id FROM categories WHERE name = 'accessories'),     'USB hubs');

-- Assign categories to products by name pattern.
-- CASE stops at the first match, so more specific patterns come first.
UPDATE products AS p
SET category_id = c.category_id
FROM categories AS c
WHERE c.name = CASE
                   WHEN p.name ILIKE '%mouse pad%'    THEN 'mouse pads'
                   WHEN p.name ILIKE '%mouse%'        THEN 'mice'
                   WHEN p.name ILIKE '%keyboard%'     THEN 'keyboards'
                   WHEN p.name ILIKE '%cable%'        THEN 'cables'
                   WHEN p.name ILIKE '%hubs%'         THEN 'USB hubs'
                   WHEN p.name ILIKE '%monitor%'      THEN 'monitors'
                   WHEN p.name ILIKE '%laptop stand%' THEN 'laptop stands'
                   WHEN p.name ILIKE '%webcam%'       THEN 'webcams'
                   WHEN p.name ILIKE '%headphones%'   THEN 'headphones'
                   WHEN p.name ILIKE '%speaker%'      THEN 'speakers'
                   WHEN p.name ILIKE '%SSD%'          THEN 'SSDs'
                   WHEN p.name ILIKE '%charger%'      THEN 'chargers'
               END;

-- Post-check: report products left without a category
DO $$
DECLARE
    products_without_category TEXT;
BEGIN
    SELECT string_agg(product_id::text, ', ' ORDER BY product_id)
    INTO products_without_category
    FROM products
    WHERE category_id IS NULL;

    IF products_without_category IS NOT NULL THEN
        RAISE NOTICE 'Products without category: %', products_without_category;
    ELSE
        RAISE NOTICE 'All products have a category';
    END IF;
END $$;

-- Record the migration
INSERT INTO schema_migrations (version, description)
VALUES ('007', 'add categories table and products.category_id');

COMMIT;