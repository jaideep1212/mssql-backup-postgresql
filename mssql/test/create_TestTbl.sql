-- =============================================================
-- create_TestTbl.sql  -  small all-types test table in LocalTestDB.
--
-- Exercises every data type the replicator must map, so type fidelity is
-- proven on a tiny table instead of the big real ones:
--   text, hash (varbinary 64), encrypted blob (varbinary max), datetime,
--   decimal, integer, boolean.
--
-- The EncField holds a Fernet-ENCRYPTED value (produced by seed_testtbl.py using
-- the same key the source app uses), so the downstream decryption round-trip can
-- be verified end to end.
--
-- Run against LocalTestDB (as a login that can CREATE TABLE + grant to svcreader).
-- =============================================================

IF OBJECT_ID('dbo.TestTbl', 'U') IS NOT NULL
    DROP TABLE dbo.TestTbl;
GO

CREATE TABLE dbo.TestTbl (
    Id           INT IDENTITY(1,1) PRIMARY KEY,   -- INT IDENTITY, like the real tables
    TextField    NVARCHAR(200)   NULL,            -- plain unicode text
    HashField    VARBINARY(64)   NULL,            -- e.g. a SHA-256 hash (-> hex downstream)
    EncField     VARBINARY(MAX)  NULL,            -- Fernet-encrypted bytes (-> decrypt downstream)
    DateField    DATETIME2       NULL,            -- datetime2 -> timestamp
    DecimalField DECIMAL(18,4)   NULL,            -- fixed precision -> numeric(18,4)
    IntField     INT             NULL,            -- integer
    BoolField    BIT             NULL             -- bit -> boolean
);
GO

-- Let the replicator's read-only login see it (same grant the real tables have).
GRANT SELECT ON dbo.TestTbl TO svcreader;
GO

PRINT 'dbo.TestTbl created and granted to svcreader.';
GO
