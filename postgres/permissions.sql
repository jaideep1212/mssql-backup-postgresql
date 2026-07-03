-- =============================================================
-- postgres/permissions.sql
-- Dedicated least-privilege role for the replicator (TARGET side).
--
-- The replicator on the Postgres side does: TRUNCATE + INSERT into the 11
-- mirror tables, and CREATE/DROP/INSERT on transient <table>_staging tables.
-- So it needs write + create-in-schema, NOT superuser (get it off 'admin').
--
-- This is the SIMPLE / PUBLIC variant: tables stay in schema 'public' and the
-- role gets explicit grants. No code changes to snapshot.py or schema.sql.
-- (The tidier alternative - a dedicated 'mirror' schema owned by the role -
--  is noted at the bottom; it would require referencing mirror.* in the code.)
--
-- Run as a superuser (admin) against household_test:
--   docker exec -i postgres psql -U admin -d household_test < permissions.sql
-- Replace the password before running.
-- =============================================================

-- ---- 1. Login role (cluster-wide) ------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'svcbackup') THEN
        CREATE ROLE svcbackup LOGIN PASSWORD 'CHANGE_ME_STRONG_PASSWORD';
        RAISE NOTICE '[postgres] Created role svcbackup.';
    ELSE
        RAISE NOTICE '[postgres] Role svcbackup already exists - no action.';
    END IF;
END $$;

-- ---- 2. Let the role work in schema public ---------------------------------
-- USAGE = see the schema; CREATE = make the _staging tables the swap needs.
GRANT USAGE, CREATE ON SCHEMA public TO svcbackup;

-- ---- 3. Rights on the existing mirror tables -------------------------------
-- SELECT (read-back for the swap), INSERT (load), TRUNCATE (clear before swap).
GRANT SELECT, INSERT, TRUNCATE ON ALL TABLES IN SCHEMA public TO svcbackup;

-- ---- 4. Future tables inherit the same grants automatically ----------------
-- So adding a mirror table later needs no permission change here.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, TRUNCATE ON TABLES TO svcbackup;

-- NOTE: staging tables are created BY svcbackup, so it owns them and can
-- INSERT/DROP them freely - no extra grant needed for those.

-- =============================================================
-- TIDIER ALTERNATIVE (not active): give the role its own schema it owns
-- outright, so it can do anything inside 'mirror' and nothing outside it.
-- Requires snapshot.py + schema.sql to use 'mirror.<table>' instead of public.
--
--   CREATE SCHEMA mirror AUTHORIZATION svcbackup;
--   -- (then create all 11 mirror tables inside schema 'mirror')
-- =============================================================
