-- =========================================================
-- 00_drop_tables.sql
-- Removes all tables of the online shop database, so the
-- schema can be rebuilt from scratch.
--
-- WARNING: this deletes the tables and ALL their data.
--
-- Tables are dropped in reverse dependency order: tables that
-- reference others (children) first, then the tables they
-- reference (parents). Otherwise the foreign keys would block
-- the drop.
--
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -f schema/00_drop_tables.sql
-- =========================================================

DROP TABLE IF EXISTS order_items;   -- references orders and products
DROP TABLE IF EXISTS orders;        -- references customers
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS customers;
