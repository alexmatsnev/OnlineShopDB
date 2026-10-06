-- =========================================================
-- 04_window_functions.sql
-- Practice: window functions - calculations across related
-- rows WITHOUT collapsing them into groups.
--
-- Run in psql:  \i queries/04_window_functions.sql
-- Results in comments assume only the sample data is loaded.
-- =========================================================


-- ---------------------------------------------------------
-- 1. Window vs GROUP BY
-- ---------------------------------------------------------

-- 1.1 GROUP BY: one row per customer
SELECT customer_id, count(*) AS orders
FROM orders
GROUP BY customer_id
ORDER BY customer_id;

-- 1.2 Window: every order stays, and each row also shows how many
--     orders its customer has in total
SELECT order_id,
       customer_id,
       count(*) OVER (PARTITION BY customer_id) AS customer_orders
FROM orders
ORDER BY customer_id, order_id;

-- 1.3 OVER () with nothing inside: the whole result is one window.
--     Each product with the overall average price next to it.
SELECT name,
       price,
       round(avg(price) OVER (), 2) AS avg_price_all
FROM products
ORDER BY price;


-- ---------------------------------------------------------
-- 2. Shares of a total
-- ---------------------------------------------------------

-- 2.1 Each order line with its order's total and its share in percent
SELECT order_id,
       product_id,
       quantity * unit_price                                   AS line_total,
       sum(quantity * unit_price) OVER (PARTITION BY order_id) AS order_total,
       round(100.0 * quantity * unit_price
             / sum(quantity * unit_price) OVER (PARTITION BY order_id), 1) AS percent_of_order
FROM order_items
ORDER BY order_id, product_id;


-- ---------------------------------------------------------
-- 3. Ranking: row_number, rank, dense_rank, ntile
-- ---------------------------------------------------------

-- 3.1 Rank customers by number of orders. Customers 1 and 2 both
--     have 3 orders, so the three functions differ on ties.
WITH counts AS (
    SELECT customer_id, count(*) AS orders
    FROM orders
    GROUP BY customer_id
)
SELECT customer_id,
       orders,
       row_number() OVER (ORDER BY orders DESC) AS row_num,    -- unique; order among ties is arbitrary
       rank()       OVER (ORDER BY orders DESC) AS rnk,        -- ties share a number, then skip
       dense_rank() OVER (ORDER BY orders DESC) AS dense_rnk   -- ties share a number, no skip
FROM counts
ORDER BY orders DESC, customer_id;

-- 3.2 Deterministic row_number: add a unique column as tie-breaker
WITH counts AS (
    SELECT customer_id, count(*) AS orders
    FROM orders
    GROUP BY customer_id
)
SELECT customer_id,
       orders,
       row_number() OVER (ORDER BY orders DESC, customer_id) AS row_num
FROM counts
ORDER BY row_num;

-- 3.3 ntile: split customers into 4 spending groups (1 = top spenders)
WITH spent AS (
    SELECT o.customer_id, sum(oi.quantity * oi.unit_price) AS total
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.order_id
    WHERE o.status <> 'cancelled'
    GROUP BY o.customer_id
)
SELECT customer_id,
       total,
       ntile(4) OVER (ORDER BY total DESC) AS spending_group
FROM spent
ORDER BY total DESC;


-- ---------------------------------------------------------
-- 4. Top N per group (filtering on a window result)
-- ---------------------------------------------------------
--     Window functions cannot be used in WHERE, so compute them
--     in a CTE first, then filter in the outer query.

-- 4.1 Each customer's largest order
WITH order_totals AS (
    SELECT o.customer_id,
           o.order_id,
           sum(oi.quantity * oi.unit_price) AS total
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.order_id
    GROUP BY o.customer_id, o.order_id
),
ranked AS (
    SELECT customer_id,
           order_id,
           total,
           row_number() OVER (PARTITION BY customer_id
                              ORDER BY total DESC, order_id) AS rn
    FROM order_totals
)
SELECT customer_id, order_id, total
FROM ranked
WHERE rn = 1
ORDER BY customer_id;

-- 4.2 Each customer's FIRST order (compare with the LATERAL solution
--     in 02_joins.sql)
WITH numbered AS (
    SELECT customer_id,
           order_id,
           order_date,
           row_number() OVER (PARTITION BY customer_id
                              ORDER BY order_date) AS rn
    FROM orders
)
SELECT customer_id, order_id, order_date
FROM numbered
WHERE rn = 1
ORDER BY customer_id;
--     PostgreSQL-only shortcut for the same thing:
--     SELECT DISTINCT ON (customer_id) customer_id, order_id, order_date
--     FROM orders ORDER BY customer_id, order_date;


-- ---------------------------------------------------------
-- 5. Running totals and the ORDER BY trap
-- ---------------------------------------------------------

-- 5.1 TRAP: the same count, with and without ORDER BY in the window.
--     Without ORDER BY: total per customer on every row.
--     With ORDER BY:    running count ("orders so far").
SELECT customer_id,
       order_id,
       order_date::date AS order_day,
       count(*) OVER (PARTITION BY customer_id)                     AS total_orders,
       count(*) OVER (PARTITION BY customer_id ORDER BY order_date) AS orders_so_far
FROM orders
ORDER BY customer_id, order_date;

-- 5.2 Monthly revenue with a running total
WITH monthly AS (
    SELECT date_trunc('month', o.order_date)::date AS month,
           sum(oi.quantity * oi.unit_price)        AS revenue
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.order_id
    WHERE o.status <> 'cancelled'
    GROUP BY month
)
SELECT month,
       revenue,
       sum(revenue) OVER (ORDER BY month) AS running_total
FROM monthly
ORDER BY month;

-- 5.3 TRAP: RANGE (the default) vs ROWS when there are ties.
--     Products 1-5 share the same created_at. With the default frame,
--     tied rows are counted together (5, 5, 5, 5, 5); with ROWS,
--     the count grows one row at a time (1, 2, 3, 4, 5).
SELECT product_id,
       name,
       created_at::date AS created_day,
       count(*) OVER (ORDER BY created_at) AS range_default,
       count(*) OVER (ORDER BY created_at
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rows_frame
FROM products
ORDER BY created_at, product_id;


-- ---------------------------------------------------------
-- 6. Moving averages (custom frames)
-- ---------------------------------------------------------

-- 6.1 3-month moving average of revenue
--     (current month and the 2 before it)
WITH monthly AS (
    SELECT date_trunc('month', o.order_date)::date AS month,
           sum(oi.quantity * oi.unit_price)        AS revenue
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.order_id
    WHERE o.status <> 'cancelled'
    GROUP BY month
)
SELECT month,
       revenue,
       round(avg(revenue) OVER (ORDER BY month
                                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3m
FROM monthly
ORDER BY month;
--     Note: the first two months average fewer than 3 values.


-- ---------------------------------------------------------
-- 7. Comparing with other rows: lag and lead
-- ---------------------------------------------------------

-- 7.1 Month-over-month revenue change
WITH monthly AS (
    SELECT date_trunc('month', o.order_date)::date AS month,
           sum(oi.quantity * oi.unit_price)        AS revenue
    FROM orders AS o
    JOIN order_items AS oi ON oi.order_id = o.order_id
    WHERE o.status <> 'cancelled'
    GROUP BY month
)
SELECT month,
       revenue,
       lag(revenue) OVER (ORDER BY month)           AS previous_month,
       revenue - lag(revenue) OVER (ORDER BY month) AS change,
       round(100.0 * (revenue - lag(revenue) OVER (ORDER BY month))
             / NULLIF(lag(revenue) OVER (ORDER BY month), 0), 1) AS change_percent
FROM monthly
ORDER BY month;
--     The first month has no previous row, so lag() returns NULL.
--     NULLIF(..., 0) avoids division by zero.

-- 7.2 Days between a customer's consecutive orders
SELECT customer_id,
       order_id,
       order_date::date AS order_day,
       order_date::date
         - lag(order_date::date) OVER (PARTITION BY customer_id
                                       ORDER BY order_date) AS days_since_previous
FROM orders
ORDER BY customer_id, order_date;

-- 7.3 lead: each order with the date of the customer's NEXT order
SELECT customer_id,
       order_id,
       order_date::date AS order_day,
       lead(order_date::date) OVER (PARTITION BY customer_id
                                    ORDER BY order_date) AS next_order_day
FROM orders
ORDER BY customer_id, order_date;


-- ---------------------------------------------------------
-- 8. first_value / last_value and named windows
-- ---------------------------------------------------------

-- 8.1 TRAP: last_value with the default frame returns the CURRENT row.
--     WINDOW w AS (...) defines a reusable named window.
SELECT customer_id,
       order_id,
       order_date::date AS order_day,
       first_value(order_id) OVER w AS first_order,
       last_value(order_id)  OVER w AS last_order_wrong,
       last_value(order_id)  OVER (w ROWS BETWEEN UNBOUNDED PRECEDING
                                          AND UNBOUNDED FOLLOWING) AS last_order_correct
FROM orders
WINDOW w AS (PARTITION BY customer_id ORDER BY order_date)
ORDER BY customer_id, order_date;


-- ---------------------------------------------------------
-- 9. Windows on top of GROUP BY
-- ---------------------------------------------------------

-- 9.1 Orders per month and each month's share of all orders.
--     count(*) is the normal aggregate per group;
--     sum(count(*)) OVER () adds up those group counts.
SELECT date_trunc('month', order_date)::date                AS month,
       count(*)                                             AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1)   AS percent_of_orders
FROM orders
GROUP BY month
ORDER BY month;


-- =========================================================
-- Exercises
-- =========================================================
-- E1. For each product, show its price, the average price of all
--     products, and the difference between them.
-- E2. Number each customer's orders 1, 2, 3, ... in date order.
-- E3. For each product, show its rank by revenue (dense_rank), and
--     list only products in the top 3 ranks.
-- E4. Find the most expensive product in each price level
--     ('budget' < 10 000, 'mid-range' < 50 000, else 'premium').
-- E5. Show the cumulative number of registered customers over time,
--     one row per customer, ordered by registration date.
-- E6. For each order, show its total and the total of the same
--     customer's previous order.
