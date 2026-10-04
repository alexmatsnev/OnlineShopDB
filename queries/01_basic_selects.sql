-- =========================================================
-- 01_basic_selects.sql
-- Practice: selecting, filtering, sorting, expressions.
-- Single-table queries only.
--
-- Run in psql:  \i queries/01_basic_selects.sql
-- or one query at a time by copying it into psql.
-- Results in comments assume only the sample data is loaded.
-- =========================================================


-- ---------------------------------------------------------
-- 1. Selecting columns
-- ---------------------------------------------------------

-- 1.1 All columns of all products
SELECT * FROM products;

-- 1.2 Only some columns, in a chosen order
SELECT name, price, stock_quantity
FROM products;

-- 1.3 Column aliases with AS (double quotes allow spaces and capitals)
SELECT first_name AS "First name",
       last_name  AS "Last name",
       email
FROM customers;

-- 1.4 Calculated column: value of stock per product
SELECT name,
       price,
       stock_quantity,
       price * stock_quantity AS stock_value
FROM products;

-- 1.5 Joining text with || : full name
SELECT first_name || ' ' || last_name AS full_name, email
FROM customers;


-- ---------------------------------------------------------
-- 2. Filtering with WHERE
-- ---------------------------------------------------------

-- 2.1 Products more expensive than 20 000
SELECT name, price
FROM products
WHERE price > 20000;

-- 2.2 Several conditions with AND: in stock and cheaper than 10 000
SELECT name, price, stock_quantity
FROM products
WHERE stock_quantity > 0
  AND price < 10000;

-- 2.3 OR: orders that are new or paid (not yet shipped)
SELECT order_id, status, order_date
FROM orders
WHERE status = 'new'
   OR status = 'paid';

-- 2.4 The same with IN (shorter when there are several values)
SELECT order_id, status, order_date
FROM orders
WHERE status IN ('new', 'paid');

-- 2.5 Range with BETWEEN (both ends included)
SELECT name, price
FROM products
WHERE price BETWEEN 10000 AND 30000;

-- 2.6 Date range: orders placed in the summer of 2026
--     (>= start and < next day is safer than BETWEEN for timestamps)
SELECT order_id, order_date, status
FROM orders
WHERE order_date >= '2026-06-01'
  AND order_date <  '2026-09-01';

-- 2.7 Text patterns with LIKE: % = any characters
SELECT name FROM products
WHERE name LIKE 'USB%';

-- 2.8 Case-insensitive pattern with ILIKE (PostgreSQL extension)
SELECT name FROM products
WHERE name ILIKE '%mouse%';

-- 2.9 Missing values: NULL is checked with IS NULL, never with = NULL
SELECT first_name, last_name, phone
FROM customers
WHERE phone IS NULL;

-- 2.10 Customers who do have an address
SELECT first_name, last_name, address
FROM customers
WHERE address IS NOT NULL;

-- 2.11 NOT: everything except delivered orders
SELECT order_id, status
FROM orders
WHERE NOT status = 'delivered';   -- same as: status <> 'delivered'


-- ---------------------------------------------------------
-- 3. Sorting and limiting
-- ---------------------------------------------------------

-- 3.1 Products from cheapest to most expensive
SELECT name, price
FROM products
ORDER BY price;            -- ASC (ascending) is the default

-- 3.2 Most expensive first
SELECT name, price
FROM products
ORDER BY price DESC;

-- 3.3 Sorting by several columns: by last name, then first name
SELECT last_name, first_name
FROM customers
ORDER BY last_name, first_name;

-- 3.4 Top 3 most expensive products
SELECT name, price
FROM products
ORDER BY price DESC
LIMIT 3;

-- 3.5 Paging: products 4-6 in price order (skip 3, take 3)
SELECT name, price
FROM products
ORDER BY price DESC
LIMIT 3 OFFSET 3;

-- 3.6 The 5 most recent orders
SELECT order_id, order_date, status
FROM orders
ORDER BY order_date DESC
LIMIT 5;


-- ---------------------------------------------------------
-- 4. DISTINCT, CASE and functions
-- ---------------------------------------------------------

-- 4.1 Which statuses are used? (each value once)
SELECT DISTINCT status
FROM orders
ORDER BY status;

-- 4.2 Label products by price level with CASE
SELECT name,
       price,
       CASE
           WHEN price < 10000  THEN 'budget'
           WHEN price < 50000  THEN 'mid-range'
           ELSE 'premium'
       END AS price_level
FROM products
ORDER BY price;

-- 4.3 Stock status, including the out-of-stock product
SELECT name,
       stock_quantity,
       CASE WHEN stock_quantity = 0 THEN 'out of stock'
            WHEN stock_quantity < 15 THEN 'low'
            ELSE 'ok'
       END AS stock_status
FROM products;

-- 4.4 Replace NULL with a default value using COALESCE
SELECT first_name, last_name,
       COALESCE(phone, 'no phone') AS phone
FROM customers;

-- 4.5 Text functions: upper/lower case, length
SELECT upper(last_name)  AS last_name_upper,
       lower(email)      AS email_lower,
       length(email)     AS email_length
FROM customers;

-- 4.6 City = the part of the address before the first comma
SELECT first_name, last_name,
       split_part(address, ',', 1) AS city
FROM customers;

-- 4.7 Date parts: year, month and weekday of each order
SELECT order_id,
       order_date,
       EXTRACT(YEAR  FROM order_date) AS year,
       EXTRACT(MONTH FROM order_date) AS month,
       to_char(order_date, 'Day')     AS weekday
FROM orders;

-- 4.8 How long ago was each order placed?
SELECT order_id,
       order_date,
       now() - order_date AS age
FROM orders
ORDER BY order_date DESC;

-- 4.9 Price with 12% VAT, rounded to whole tenge
SELECT name,
       price,
       round(price * 1.12) AS price_with_vat
FROM products;


-- =========================================================
-- Exercises (try on your own)
-- =========================================================
-- E1. List customers registered in 2026-03 or later, newest first.
-- E2. Find products whose description mentions 'USB' (any case).
-- E3. Show the 3 cheapest products that are in stock.
-- E4. List all cities where customers live, each city once.
-- E5. Show orders that are not cancelled and were placed before
--     2026-05-01, sorted by date.
-- E6. For each product, show its name and a column 'discount_price'
--     that is 10% lower than price, rounded to tens.
