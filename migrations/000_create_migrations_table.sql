-- =========================================================
-- 000_create_migrations_table.sql
-- Purpose:  Create a table to track applied migrations.
-- Depends:  nothing
-- Notes:    Runs before applying all other migrations.
-- 
-- Run as alex_mav, connected to online_shop:
--   psql -U alex_mav -d online_shop -v ON_ERROR_STOP=1 -f migrations/000_create_migrations_table.sql
-- =========================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- Pre-check: nothing to verify (new table)

-- Changes
CREATE TABLE schema_migrations (
    version     VARCHAR(20) PRIMARY KEY,
    description TEXT        NOT NULL,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Post-check: nothing to verify

-- Record the migration
INSERT INTO schema_migrations (version, description)
VALUES ('000', 'create migrations table');

COMMIT;