-- =============================================================
-- create_test_tbl.sql  -  Postgres mirror of dbo.TestTbl in household_test.
--
-- Type mapping (SQL Server -> PostgreSQL):
--   INT IDENTITY   -> bigint          (id carried verbatim, Option A keys)
--   NVARCHAR(200)  -> text
--   VARBINARY(64)  -> bytea           (hash bytes)
--   VARBINARY(MAX) -> bytea           (encrypted blob, raw bytes)
--   DATETIME2      -> timestamp       (without time zone)
--   DECIMAL(18,4)  -> numeric(18,4)   (exact precision, no float rounding)
--   INT            -> integer
--   BIT            -> boolean
--
-- FK-free, plain bigint PK - so the replicator's TRUNCATE + reload swap works.
-- Run against household_test as a role that can CREATE and grant to svcbackup.
-- =============================================================

DROP TABLE IF EXISTS public.test_tbl CASCADE;

CREATE TABLE public.test_tbl (
    id            bigint PRIMARY KEY,
    text_field    text,
    hash_field    bytea,
    enc_field     bytea,
    date_field    timestamp,
    decimal_field numeric(18,4),
    int_field     integer,
    bool_field    boolean
);

-- Match the grants the real mirror tables have.
GRANT SELECT, INSERT, TRUNCATE ON public.test_tbl TO svcbackup;
