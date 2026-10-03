-- =========================================================
-- 01_tables.sql
-- Creates the tables of the online shop database.
-- Tables are created in dependency order: parent tables first
-- (customers, products), then tables that reference them
-- (orders, order_items).
--
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -f schema/01_tables.sql
-- =========================================================


-- ---------------------------------------------------------
-- customers: people who buy in the shop
-- ---------------------------------------------------------
CREATE TABLE customers (
    customer_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name   VARCHAR(50)  NOT NULL,
    last_name    VARCHAR(50)  NOT NULL,
    email        VARCHAR(255) NOT NULL UNIQUE,
    phone        VARCHAR(20),
    address      TEXT,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);


-- ---------------------------------------------------------
-- products: items available for sale
-- ---------------------------------------------------------
CREATE TABLE products (
    product_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           VARCHAR(150)   NOT NULL,
    description    TEXT,
    price          NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    stock_quantity INTEGER        NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    created_at     TIMESTAMPTZ    NOT NULL DEFAULT now()
);


-- ---------------------------------------------------------
-- orders: one customer -> many orders
-- ---------------------------------------------------------
CREATE TABLE orders (
    order_id         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id      INTEGER     NOT NULL REFERENCES customers (customer_id),
    order_date       TIMESTAMPTZ NOT NULL DEFAULT now(),
    status           VARCHAR(20) NOT NULL DEFAULT 'new'
                     CHECK (status IN ('new', 'paid', 'shipped', 'delivered', 'cancelled')),
    shipping_address TEXT
);


-- ---------------------------------------------------------
-- order_items: links orders and products (many-to-many)
-- ---------------------------------------------------------
CREATE TABLE order_items (
    order_item_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      INTEGER        NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
    product_id    INTEGER        NOT NULL REFERENCES products (product_id),
    quantity      INTEGER        NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),  -- price at the moment of purchase
    UNIQUE (order_id, product_id)  -- each product appears only once per order
);