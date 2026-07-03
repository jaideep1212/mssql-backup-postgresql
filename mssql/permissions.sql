-- =============================================================
-- mssql/permissions.sql
-- Dedicated least-privilege SQL login for the replicator (SOURCE side).
--
-- The replicator ONLY reads the 11 replicated tables and reads/writes the
-- BackupOutbox. It never writes your business tables and never executes SPs.
--
-- Requires: SQL Server in MIXED MODE auth (SQL logins enabled alongside
-- Windows auth). If the instance is Windows-auth-only, enable Mixed Mode
-- (Server Properties > Security > "SQL Server and Windows Auth mode") + restart.
--
-- Run as a sysadmin (e.g. via sqlcmd or SSMS) against the instance.
-- Replace the password before running; keep it only in Jenkins creds / the Pi .env.
-- =============================================================

-- ---- 1. Server-level login (cluster-wide identity) --------------------------
USE [master];
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'svcreader')
BEGIN
    CREATE LOGIN [svcreader]
        WITH PASSWORD = N'CHANGE_ME_STRONG_PASSWORD',
             CHECK_POLICY = ON;
    PRINT '[mssql] Created login svcreader.';
END
ELSE
    PRINT '[mssql] Login svcreader already exists - no action.';
GO

-- ---- 2. Database user in LocalTestDB ----------------------------------------
USE [LocalTestDB];
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'svcreader')
BEGIN
    CREATE USER [svcreader] FOR LOGIN [svcreader];
    PRINT '[mssql] Created user svcreader in LocalTestDB.';
END
ELSE
    PRINT '[mssql] User already exists in LocalTestDB - no action.';
GO

-- ---- 3. Least-privilege grants ----------------------------------------------
-- OPTION A (default, tighter): explicit SELECT on exactly the 11 replicated
-- tables. The reader can see ONLY what it replicates. Add a GRANT line when
-- you add a table to replication.
GRANT SELECT ON dbo.DimAccounts                TO [svcreader];
GRANT SELECT ON dbo.DimEntities                TO [svcreader];
GRANT SELECT ON dbo.DimMutualFunds             TO [svcreader];
GRANT SELECT ON dbo.DimUsers                   TO [svcreader];
GRANT SELECT ON dbo.DimUsers_S                 TO [svcreader];
GRANT SELECT ON dbo.FactAccountBrokerMappings  TO [svcreader];
GRANT SELECT ON dbo.FactAliases                TO [svcreader];
GRANT SELECT ON dbo.FactDeposits               TO [svcreader];
GRANT SELECT ON dbo.FactMutualFundTransactions TO [svcreader];
GRANT SELECT ON dbo.FactOtherContacts          TO [svcreader];
GRANT SELECT ON dbo.FactStockTransactions      TO [svcreader];
GO

-- OPTION B (broad, less maintenance): read EVERY table in the DB, now and
-- future. Comment out Option A above and uncomment this instead if preferred.
-- ALTER ROLE db_datareader ADD MEMBER [svcreader];
-- GO

-- ---- 4. Outbox: the consumer claims/completes/releases/reaps ---------------
-- Needs SELECT + UPDATE (db_datareader would only give SELECT).
GRANT SELECT, UPDATE ON dbo.BackupOutbox TO [svcreader];
GO

PRINT '[mssql] Permissions applied for svcreader on LocalTestDB.';
GO
