-- =============================================================
-- 01_backup_outbox_table.sql
-- Append-outbox for the backup/replication signal.
--
-- Each stored procedure that writes a replicated table INSERTs one
-- row here (inside its own transaction, before COMMIT) listing the
-- tables it touched. The consumer runs every X minutes and:
--   1. Atomically CLAIMS all pending rows (0 -> 2) capturing their IDs
--   2. Derives the DISTINCT set of tables from the claimed rows
--   3. Full-snapshots each distinct table once into PostgreSQL
--   4. Marks ONLY the claimed IDs done (2 -> 1)
-- Rows inserted mid-cycle stay at 0 and are picked up next cycle.
--
-- No seed file and no per-table pre-registration: a brand-new table
-- self-registers the first time any SP inserts a row naming it.
--
-- Idempotent: safe to run repeatedly via sqlcmd against any DB.
-- =============================================================

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.BackupOutbox', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BackupOutbox
    (
        EventId      BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        TableNames   NVARCHAR(MAX) NOT NULL,   -- JSON array, e.g. N'["dbo.DimUsers","dbo.DimUsers_S"]'
        -- 0 = pending, 2 = claimed/in-progress, 1 = done
        BackupDone   TINYINT       NOT NULL
            CONSTRAINT DF_BackupOutbox_BackupDone DEFAULT (0),
        CreatedUtc   DATETIME2(3)  NOT NULL
            CONSTRAINT DF_BackupOutbox_CreatedUtc DEFAULT (SYSUTCDATETIME()),
        ModifiedUtc  DATETIME2(3)  NULL,        -- last state change (claimed / done / reset)
        Attempts     INT           NOT NULL
            CONSTRAINT DF_BackupOutbox_Attempts DEFAULT (0),
        LastError    NVARCHAR(MAX) NULL,
        CONSTRAINT CK_BackupOutbox_BackupDone CHECK (BackupDone IN (0, 1, 2))
    );

    -- Filtered index: fast "find pending or stuck-claimed work" scans,
    -- staying small even as completed history grows to millions of rows.
    CREATE INDEX IX_BackupOutbox_Pending
        ON dbo.BackupOutbox (EventId)
        INCLUDE (TableNames)
        WHERE BackupDone IN (0, 2);

    PRINT '[01] Created table dbo.BackupOutbox.';
END
ELSE
BEGIN
    PRINT '[01] Table dbo.BackupOutbox already exists - no action.';
END
GO
