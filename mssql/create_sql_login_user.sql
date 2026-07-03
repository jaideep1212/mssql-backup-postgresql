-- On the SQL Server instance (requires Mixed Mode auth enabled)
USE [master];
CREATE LOGIN svcreader WITH PASSWORD = 'YOUR_PASSWORD_HERE'; -- replace with a strong password
GO

USE [LocalTestDB];
CREATE USER svcreader FOR LOGIN svcreader;

-- Read-only on the replicated tables (db_datareader covers all tables;
-- tighten to specific tables with explicit GRANTs if you prefer).
ALTER ROLE db_datareader ADD MEMBER svcreader;

-- The consumer also claims/completes the outbox, so it needs write there.
GRANT SELECT, UPDATE ON dbo.BackupOutbox TO svcreader;
GO