-- =========================================================
-- 03_aggregations.sql
-- Practice: aggregate functions, GROUP BY, HAVING, reports.
--
-- Run in psql:  \i queries/03_aggregations.sql
-- Most revenue queries exclude cancelled orders, as a real
-- shop report would.
-- =========================================================


-- ---------------------------------------------------------
-- 1. Aggregate functions over a whole table
-- ---------------------------------------------------------

-- 1.1 How many customers are there?
SELECT count(*) AS customers FROM customers;

-- 1.2 count(*) vs count(column): count(column) skips NULLs
SELECT count(*)     AS all_customers,
       count(phone) AS customers_with_phone
FROM customers;

-- 1.3 Price statistics
SELECT min(price)            AS cheapest,
       max(price)            AS most_expensive,
       round(avg(price), 2)  AS average_price,
       sum(stock_quantity)   AS items_in_stock
FROM products;

-- 1.4 Total value of goods in the warehouse
SELECT sum(price * stock_quantity) AS stock_value
FROM products;

-- 1.5 Date range of orders
SELECT min(order_date) AS first_order,
       max(order_date) AS last_order
FROM orders;

-- 1.6 How many different customers have ordered?
SELECT count(DISTINCT customer_id) AS ordering_customers
FROM orders;


-- ---------------------------------------------------------
-- 2. GROUP BY: one result row per group
-- ---------------------------------------------------------

-- 2.1 Number of orders per status
SELECT status, count(*) AS orders
FROM orders
GROUP BY status
ORDER BY orders DESC;

-- 2.2 Total of each order
SELECT order_id,
       sum(quantity * unit_price) AS order_total
FROM order_items
GROUP BY order_id
ORDER BY order_id;

-- 2.3 Number of orders per customer, with names
--     (every non-aggregated column must be in GROUP BY)
SELECT c.customer_id,
       c.first_name,
       c.last_name,
       count(o.order_id) AS orders
FROM customers AS c
LEFT JOIN orders AS o ON o.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY orders DESC, c.customer_id;
--     count(o.order_id), not count(*): customers without orders
--     get 0 instead of 1 (the LEFT JOIN row with NULLs)

-- 2.4 Total spent by each customer (excluding cancelled orders)
SELECT c.first_name || ' ' || c.last_name AS customer,
       sum(oi.quantity * oi.unit_price)   AS total_spent
FROM customers AS c
JOIN orders      AS o  ON o.customer_id = c.customer_id
JOIN order_items AS oi ON oi.order_id   = o.order_id
WHERE o.status <> 'cancelled'
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY total_spent DESC;

-- 2.5 Best-selling products by quantity
SELECT p.name,
       sum(oi.quantity)                 AS units_sold,
       sum(oi.quantity * oi.unit_price) AS revenue
FROM products AS p
JOIN order_items AS oi ON oi.product_id = p.product_id
JOIN orders      AS o  ON o.order_id    = oi.order_id
WHERE o.status <> 'cancelled'
GROUP BY p.product_id, p.name
ORDER BY units_sold DESC
LIMIT 5;

-- 2.6 Customers per city
SELECT split_part(address, ',', 1) AS city,
       count(*)                    AS customers
FROM customers
WHERE address IS NOT NULL
GROUP BY city
ORDER BY customers DESC, city;


-- ---------------------------------------------------------
-- 3. HAVING: filtering groups
-- ---------------------------------------------------------
--     WHERE filters rows BEFORE grouping,
--     HAVING filters groups AFTER grouping.

-- 3.1 Customers with more than one order
SELECT customer_id, count(*) AS orders
FROM orders
GROUP BY customer_id
HAVING count(*) > 1
ORDER BY orders DESC;

-- 3.2 Orders worth more than 50 000
SELECT order_id, sum(quantity * unit_price) AS order_total
FROM order_items
GROUP BY order_id
HAVING sum(quantity * unit_price) > 50000
ORDER BY order_total DESC;

-- 3.3 WHERE and HAVING together: among non-cancelled orders,
--     customers who spent over 100 000
SELECT o.customer_id,
       sum(oi.quantity * oi.unit_price) AS total_spent
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.order_id
WHERE o.status <> 'cancelled'                       -- rows
GROUP BY o.customer_id
HAVING sum(oi.quantity * oi.unit_price) > 100000    -- groups
ORDER BY total_spent DESC;


-- ---------------------------------------------------------
-- 4. Reports over time
-- ---------------------------------------------------------

-- 4.1 Revenue per month
SELECT date_trunc('month', o.order_date)::date AS month,
       count(DISTINCT o.order_id)              AS orders,
       sum(oi.quantity * oi.unit_price)        AS revenue
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.order_id
WHERE o.status <> 'cancelled'
GROUP BY month
ORDER BY month;

-- 4.2 New customers per month
SELECT to_char(created_at, 'YYYY-MM') AS month,
       count(*)                       AS new_customers
FROM customers
GROUP BY month
ORDER BY month;

-- 4.3 Orders per weekday (1 = Monday ... 7 = Sunday)
SELECT EXTRACT(ISODOW FROM order_date) AS weekday_no,
       to_char(order_date, 'Day')      AS weekday,
       count(*)                        AS orders
FROM orders
GROUP BY weekday_no, weekday
ORDER BY weekday_no;


-- ---------------------------------------------------------
-- 5. FILTER, CTEs and subqueries with aggregates
-- ---------------------------------------------------------

-- 5.1 FILTER: several conditional counts in one row
SELECT count(*)                                       AS all_orders,
       count(*) FILTER (WHERE status = 'delivered')   AS delivered,
       count(*) FILTER (WHERE status = 'cancelled')   AS cancelled,
       count(*) FILTER (WHERE status IN ('new', 'paid', 'shipped')) AS in_progress
FROM orders;

-- 5.2 Average order value, using a CTE for order totals
WITH order_totals AS (
    SELECT oi.order_id, sum(oi.quantity * oi.unit_price) AS total
    FROM order_items AS oi
    JOIN orders AS o ON o.order_id = oi.order_id
    WHERE o.status <> 'cancelled'
    GROUP BY oi.order_id
)
SELECT count(*)            AS orders,
       round(avg(total), 2) AS average_order_value,
       max(total)          AS biggest_order
FROM order_totals;

-- 5.3 Products priced above the average price (subquery)
SELECT name, price
FROM products
WHERE price > (SELECT avg(price) FROM products)
ORDER BY price DESC;

-- 5.4 Average number of items (lines) per order
SELECT round(avg(lines), 2) AS avg_lines_per_order
FROM (
    SELECT order_id, count(*) AS lines
    FROM order_items
    GROUP BY order_id
) AS per_order;

-- 5.5 Each customer's share of total revenue, in percent
WITH spent AS (
    SELECT o.customer_id, sum(oi.quantity * oi.unit_price) AS total
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.order_id
    WHERE o.status <> 'cancelled'
    GROUP BY o.customer_id
)
SELECT c.first_name || ' ' || c.last_name             AS customer,
       s.total,
       round(100.0 * s.total / sum(s.total) OVER (), 1) AS percent_of_revenue
FROM spent AS s
JOIN customers AS c ON c.customer_id = s.customer_id
ORDER BY s.total DESC;
--     sum(...) OVER () is a window function: the grand total
--     placed on every row, without collapsing rows into groups.


-- =========================================================
-- Exercises
-- =========================================================
-- E1. How many products are out of stock?
-- WHERE is better for count with one condition
SELECT count(*) AS out_of_stock_products
FROM products
WHERE stock_quantity = 0;

SELECT count(*) FILTER (WHERE p.stock_quantity = 0) AS out_of_stock_products
FROM products AS p; 

-- FILTER is better when we need several counts with different conditions in one query
SELECT count(*)                                             AS all_products,
       count(*) FILTER (WHERE stock_quantity = 0)           AS out_of_stock,
       count(*) FILTER (WHERE stock_quantity BETWEEN 1 AND 14) AS low_stock
FROM products;

-- E2. Show the number of items sold per product, including products
--     never sold (they should show 0).
SELECT p.product_id,
       p.name,
       COALESCE(sum(oi.quantity) FILTER (WHERE o.status <> 'cancelled'), 0) AS units_sold
FROM products AS p
LEFT JOIN order_items AS oi USING (product_id)
LEFT JOIN orders      AS o  USING (order_id)
GROUP BY p.product_id, p.name
ORDER BY p.product_id;

-- E3. Which month had the most orders?
SELECT date_trunc('month', o.order_date)::date AS max_orders_month,
	   count(*) AS orders
FROM orders AS o
GROUP BY max_orders_month
ORDER BY orders DESC
FETCH FIRST 1 ROWS WITH TIES;
-- using WITH TIES in case few months have the same max number of orders

-- E4. List customers whose average order value is above 30 000.
WITH orders_value AS (
	SELECT oi.order_id,
		   sum(oi.quantity * oi.unit_price) AS order_value
	FROM order_items AS oi
	GROUP BY oi.order_id
)
SELECT c.customer_id,
	   c.first_name || ' ' || c.last_name AS customer,
	   round(avg(ov.order_value), 2) AS avg_order_value
FROM customers AS c
INNER JOIN orders AS o USING (customer_id)
INNER JOIN orders_value AS ov USING (order_id)
WHERE o.status <> 'cancelled'
GROUP BY c.customer_id, customer
HAVING avg(ov.order_value) > 30000
ORDER BY customer_id ASC ;

-- E5. For each status, show the number of orders and their total value.
SELECT o.status AS order_status,
	   count(DISTINCT o.order_id) AS order_count,
	   COALESCE(sum(oi.quantity * oi.unit_price), 0) AS total_value
FROM orders AS o
LEFT JOIN order_items AS oi USING (order_id)
GROUP BY o.status
ORDER BY array_position(
    ARRAY['new', 'paid', 'shipped', 'delivered', 'cancelled'],
    o.status::text
);
-- use array in order to custom sort order that is defined by array order
-- cuz sorting alphabetical doesn't make sense for status values

-- E6. Find the customer who bought the most different products.
WITH target_customer AS (
	SELECT c.customer_id,
		   c.first_name || ' ' || c.last_name AS customer
	FROM customers AS c
	INNER JOIN orders AS o USING (customer_id)
	INNER JOIN order_items AS oi USING (order_id)
	INNER JOIN products AS p USING (product_id)
	GROUP BY c.customer_id, customer
	ORDER BY count(DISTINCT p.product_id) DESC
	FETCH FIRST 1 ROWS WITH TIES
)
SELECT * FROM target_customer
ORDER BY target_customer.customer_id;
-- we need CTE cuz inside the main query we need to sort in order to fetch
-- the first row. And then we need to sort for displaying results.
