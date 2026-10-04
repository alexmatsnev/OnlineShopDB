-- =========================================================
-- 02_generated_data.sql
-- Generates a large volume of random test data with
-- generate_series().
--
-- Result (approximately):
--   1 000 customers, 200 products, 10 000 orders,
--   ~30 000 order items
--
-- Run AFTER 01_sample_data.sql if sample data was inserted:
--   psql -U alex_mav -d online_shop -f seed/02_generated_data.sql
--
-- Generated rows are easy to tell apart from the hand-written
-- sample data:
--   - customer emails look like customerN@example.com
--   - product descriptions start with 'Generated product'
-- Generated orders use only generated customers and products.
-- =========================================================

BEGIN;

-- Fix the random seed, so every run produces the same data
SELECT setseed(0.42);


-- ---------------------------------------------------------
-- Customers: 1 000 rows
-- Names and cities are picked randomly from small arrays.
-- ---------------------------------------------------------
INSERT INTO customers (first_name, last_name, email, phone, address, created_at)
SELECT
    (ARRAY['Aigerim','Daniyar','Elena','Timur','Madina','Sergey','Dana',
           'Arman','Olga','Yerlan','Aruzhan','Nurlan','Anna','Bekzat','Zhanna'])
        [1 + floor(random() * 15)::int],
    (ARRAY['Nurlanov','Sadykov','Ivanov','Akhmetov','Seitkali','Petrov',
           'Zhumabekov','Kassymov','Kim','Bekov','Omarov','Smirnov','Tulegenov'])
        [1 + floor(random() * 13)::int],
    'customer' || g || '@example.com',                          -- unique by construction
    CASE WHEN random() < 0.8                                    -- ~20% have no phone
         THEN '+7701' || lpad(g::text, 7, '0') END,
    (ARRAY['Astana','Almaty','Shymkent','Karaganda','Aktobe','Pavlodar','Atyrau'])
        [1 + floor(random() * 7)::int]
        || ', Street ' || (1 + floor(random() * 200))::int,
    timestamptz '2024-01-01 00:00+05' + random() * interval '365 days'
FROM generate_series(1, 1000) AS g;


-- ---------------------------------------------------------
-- Products: 200 rows
-- ---------------------------------------------------------
INSERT INTO products (name, description, price, stock_quantity, created_at)
SELECT
    (ARRAY['Wireless mouse','Keyboard','Monitor','Headphones','USB cable',
           'Webcam','Speaker','Charger','SSD','Laptop stand'])
        [1 + floor(random() * 10)::int] || ' model ' || g,
    'Generated product #' || g,
    round((1000 + random() * 199000)::numeric, -1),             -- 1 000 .. 200 000, rounded to tens
    floor(random() * 201)::int,                                 -- 0 .. 200 in stock
    timestamptz '2024-01-01 00:00+05' + random() * interval '365 days'
FROM generate_series(1, 200) AS g;


-- ---------------------------------------------------------
-- Orders: 10 000 rows
-- Each order gets a random generated customer and a random
-- date between 2025-01-01 and 2026-10-01. The status depends
-- on how old the order is; ~5% are cancelled.
-- ---------------------------------------------------------
WITH id_range AS (
    SELECT min(customer_id) AS min_id, max(customer_id) AS max_id
    FROM customers
    WHERE email LIKE 'customer%@example.com'
),
gen AS (
    SELECT
        id_range.min_id + floor(random() * (id_range.max_id - id_range.min_id + 1))::int AS customer_id,
        timestamptz '2025-01-01 00:00+05'
            + random() * (timestamptz '2026-10-01 00:00+05' - timestamptz '2025-01-01 00:00+05')
            AS order_date,
        random() AS r_status
    FROM generate_series(1, 10000) CROSS JOIN id_range
)
INSERT INTO orders (customer_id, order_date, status, shipping_address)
SELECT
    g.customer_id,
    g.order_date,
    CASE
        WHEN g.r_status < 0.05                        THEN 'cancelled'
        WHEN g.order_date < '2026-09-01 00:00+05'     THEN 'delivered'
        WHEN g.order_date < '2026-09-20 00:00+05'     THEN 'shipped'
        WHEN g.order_date < '2026-09-28 00:00+05'     THEN 'paid'
        ELSE 'new'
    END,
    c.address
FROM gen AS g
INNER JOIN customers AS c ON c.customer_id = g.customer_id;


-- ---------------------------------------------------------
-- Order items: 1-5 different products per generated order,
-- quantity 1-3, unit_price copied from the product.
--
-- LATERAL runs the inner query once per order. The condition
-- "o.order_id IS NOT NULL" is always true, but it references
-- the outer row, which forces PostgreSQL to re-run the inner
-- query for every order (otherwise it may run it only once
-- and give every order the same products).
-- Picking rows with ORDER BY random() + LIMIT guarantees the
-- products within one order are all different, which
-- satisfies UNIQUE (order_id, product_id).
-- ---------------------------------------------------------
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT o.order_id, p.product_id, 1 + floor(random() * 3)::int, p.price
FROM orders AS o
CROSS JOIN LATERAL (
    SELECT pr.product_id, pr.price
    FROM products AS pr
    WHERE pr.description LIKE 'Generated product%'
      AND o.order_id IS NOT NULL
    ORDER BY random()
    LIMIT 1 + floor(random() * 5)::int
) AS p
WHERE NOT EXISTS (                       -- only orders that have no items yet,
    SELECT 1                             -- i.e. the newly generated ones
    FROM order_items AS oi
    WHERE oi.order_id = o.order_id
);

COMMIT;

-- Refresh table statistics so the query planner knows the new sizes
ANALYZE;

-- Show resulting row counts
SELECT 'customers'   AS table_name, count(*) AS row_count FROM customers
UNION ALL SELECT 'products',    count(*) FROM products
UNION ALL SELECT 'orders',      count(*) FROM orders
UNION ALL SELECT 'order_items', count(*) FROM order_items;
