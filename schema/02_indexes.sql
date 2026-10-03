-- =========================================================
-- 02_indexes.sql
-- Creates indexes to speed up joins and lookups.
--
-- PostgreSQL automatically indexes PRIMARY KEY and UNIQUE
-- columns, but NOT foreign key columns, so those added here.
--
-- Not needed (already covered by automatic indexes):
--   - order_items.order_id: covered by the index behind
--     UNIQUE (order_id, product_id), because order_id is its
--     first column.
--   - customers.email: covered by its UNIQUE constraint.
--
-- Run as alex_mav, connected to online_shop, after 01_tables.sql:
--   psql -U alex_mav -d online_shop -f schema/02_indexes.sql
-- =========================================================

-- Find all orders of a customer; join orders with customers
CREATE INDEX idx_orders_customer_id ON orders (customer_id);

-- Find all order items for a product; join order_items with products
CREATE INDEX idx_order_items_product_id ON order_items (product_id);