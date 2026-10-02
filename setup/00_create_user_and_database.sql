-- One-time setup: creates the application user and the database.
-- Run as the postgres superuser:
--   psql -U postgres -f setup/00_create_user_and_database.sql

-- Show messages in English (avoids encoding errors with localized messages)
SET lc_messages TO 'C';

-- Application user (replace the placeholder with your own password locally,
-- but don't commit your real password to Git)
CREATE USER alex_mav WITH PASSWORD 'change_me';

-- Database owned by the application user
CREATE DATABASE online_shop OWNER alex_mav;