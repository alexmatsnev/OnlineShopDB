-- =========================================================
-- 02_joins.sql
-- Practice: combining data from several tables.
--
-- Run in psql:  \i queries/02_joins.sql
-- Results in comments assume only the sample data is loaded.
-- Useful facts about the sample data:
--   - customers 9 (Olga) and 10 (Yerlan) have no orders
--   - products 11 and 12 were never ordered
-- =========================================================


-- ---------------------------------------------------------
-- 1. INNER JOIN: only rows that match in both tables
-- ---------------------------------------------------------

-- 1.1 Each order with the name of its customer
SELECT o.order_id,
       o.order_date,
       o.status,
       c.first_name || ' ' || c.last_name AS customer
FROM orders AS o
JOIN customers AS c ON c.customer_id = o.customer_id
ORDER BY o.order_id;

-- 1.2 Order items with product names
SELECT oi.order_id,
       p.name,
       oi.quantity,
       oi.unit_price
FROM order_items AS oi
JOIN products AS p ON p.product_id = oi.product_id
ORDER BY oi.order_id;

-- 1.3 All four tables: full details of every order line
SELECT o.order_id,
       o.order_date::date                 AS order_day,
       c.first_name || ' ' || c.last_name AS customer,
       p.name                             AS product,
       oi.quantity,
       oi.unit_price,
       oi.quantity * oi.unit_price        AS line_total
FROM orders AS o
JOIN customers   AS c  ON c.customer_id = o.customer_id
JOIN order_items AS oi ON oi.order_id   = o.order_id
JOIN products    AS p  ON p.product_id  = oi.product_id
ORDER BY o.order_id, p.name;

-- 1.4 What did Aigerim buy? (join + filter)
SELECT o.order_id, o.order_date::date AS order_day, p.name, oi.quantity
FROM customers AS c
JOIN orders      AS o  ON o.customer_id = c.customer_id
JOIN order_items AS oi ON oi.order_id   = o.order_id
JOIN products    AS p  ON p.product_id  = oi.product_id
WHERE c.email = 'aigerim.nurlanova@example.com'
ORDER BY o.order_date;

-- 1.5 USING: shorter syntax when the column has the same name
SELECT order_id, first_name, last_name, status
FROM orders
JOIN customers USING (customer_id);


-- ---------------------------------------------------------
-- 2. LEFT JOIN: keep all rows from the left table
-- ---------------------------------------------------------

-- 2.1 All customers with their orders; customers without orders
--     appear with NULL in the order columns (Olga, Yerlan)
SELECT c.customer_id,
       c.first_name,
       o.order_id,
       o.status
FROM customers AS c
LEFT JOIN orders AS o ON o.customer_id = c.customer_id
ORDER BY c.customer_id, o.order_id;

-- 2.2 Anti join with LEFT JOIN: customers who never ordered
SELECT c.customer_id, c.first_name, c.last_name
FROM customers AS c
LEFT JOIN orders AS o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL;

-- 2.3 Products that were never ordered (products 11 and 12)
SELECT p.product_id, p.name
FROM products AS p
LEFT JOIN order_items AS oi ON oi.product_id = p.product_id
WHERE oi.order_item_id IS NULL;

-- 2.4 Careful: a condition on the right table belongs in ON, not WHERE.
--     All customers, with only their DELIVERED orders:
SELECT c.first_name, o.order_id, o.status
FROM customers AS c
LEFT JOIN orders AS o
       ON o.customer_id = c.customer_id
      AND o.status = 'delivered'
ORDER BY c.customer_id;
--     Moving "o.status = 'delivered'" to WHERE would remove customers
--     without delivered orders, turning it into an inner join.


-- ---------------------------------------------------------
-- 3. RIGHT and FULL JOIN
-- ---------------------------------------------------------

-- 3.1 RIGHT JOIN: same result as 2.1, tables in reverse order
SELECT c.first_name, o.order_id
FROM orders AS o
RIGHT JOIN customers AS c ON c.customer_id = o.customer_id;

-- 3.2 FULL JOIN: compare two lists. Here: cities where customers
--     live vs. cities orders were shipped to.
WITH customer_cities AS (
    SELECT DISTINCT split_part(address, ',', 1) AS city
    FROM customers WHERE address IS NOT NULL
),
shipping_cities AS (
    SELECT DISTINCT split_part(shipping_address, ',', 1) AS city
    FROM orders WHERE shipping_address IS NOT NULL
)
SELECT cc.city AS customer_city,
       sc.city AS shipping_city
FROM customer_cities AS cc
FULL JOIN shipping_cities AS sc ON sc.city = cc.city
ORDER BY COALESCE(cc.city, sc.city);
--     NULL on the left: shipped there, but no customer lives there.
--     NULL on the right: customers live there, nothing shipped yet.


-- ---------------------------------------------------------
-- 4. CROSS JOIN: every combination
-- ---------------------------------------------------------

-- 4.1 Every customer paired with every status (10 x 5 = 50 rows)
SELECT c.first_name, s.status
FROM customers AS c
CROSS JOIN (VALUES ('new'), ('paid'), ('shipped'), ('delivered'), ('cancelled'))
           AS s (status)
ORDER BY c.first_name, s.status;


-- ---------------------------------------------------------
-- 5. Self join: a table joined with itself
-- ---------------------------------------------------------

-- 5.1 Pairs of customers living in the same city
SELECT a.first_name || ' ' || a.last_name AS customer_1,
       b.first_name || ' ' || b.last_name AS customer_2,
       split_part(a.address, ',', 1)      AS city
FROM customers AS a
JOIN customers AS b
  ON split_part(a.address, ',', 1) = split_part(b.address, ',', 1)
 AND a.customer_id < b.customer_id      -- no self-pairs, no duplicates
ORDER BY city;


-- ---------------------------------------------------------
-- 6. Semi and anti joins with EXISTS
-- ---------------------------------------------------------

-- 6.1 Semi join: customers with at least one order (each listed once)
SELECT c.customer_id, c.first_name, c.last_name
FROM customers AS c
WHERE EXISTS (
    SELECT 1 FROM orders AS o WHERE o.customer_id = c.customer_id
);

-- 6.2 Anti join: customers with no orders (same result as 2.2)
SELECT c.customer_id, c.first_name, c.last_name
FROM customers AS c
WHERE NOT EXISTS (
    SELECT 1 FROM orders AS o WHERE o.customer_id = c.customer_id
);

-- 6.3 Customers who bought headphones
SELECT c.first_name, c.last_name
FROM customers AS c
WHERE EXISTS (
    SELECT 1
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id   = o.order_id
    JOIN products    AS p  ON p.product_id  = oi.product_id
    WHERE o.customer_id = c.customer_id
      AND p.name ILIKE '%headphones%'
);


-- ---------------------------------------------------------
-- 7. LATERAL: a subquery per row
-- ---------------------------------------------------------

-- 7.1 Each customer with their most recent order
--     (LEFT JOIN keeps customers without orders)
SELECT c.first_name, c.last_name, lo.order_id, lo.order_date
FROM customers AS c
LEFT JOIN LATERAL (
    SELECT o.order_id, o.order_date
    FROM orders AS o
    WHERE o.customer_id = c.customer_id
    ORDER BY o.order_date DESC
    LIMIT 1
) AS lo ON true
ORDER BY c.customer_id;


-- =========================================================
-- Exercises (try on your own)
-- =========================================================
-- E1. List all order lines of order 5 with product name, quantity
--     and line total.
-- E2. Show every product with the IDs of the orders it appears in,
--     including products never ordered (hint: LEFT JOIN).
-- E3. Find customers who have a 'cancelled' order.
-- E4. Find customers who never bought anything costing more than
--     50 000 per unit (hint: NOT EXISTS).
-- E5. For each customer, show their FIRST order (hint: LATERAL).
-- E6. List orders shipped to an address different from the
--     customer's own address.
