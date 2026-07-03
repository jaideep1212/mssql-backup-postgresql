-- =============================================================
-- 02_consumer_cycle.reference.sql
-- REFERENCE ONLY - not deployed as a stored procedure.
-- This is the exact SQL the consumer runs each X-minute cycle.
-- Shown here as one reviewable unit; the Python consumer issues
-- these same statements (steps 1, 2, 4) around the snapshot work
-- (step 3, which happens in Python against SQL Server + PostgreSQL).
--
-- The design guarantee: only rows CLAIMED in step 1 are ever
-- completed in step 4, so rows inserted mid-cycle are never
-- marked done without being backed up.
-- =============================================================

-- -------------------------------------------------------------
-- STEP 1: Atomically claim all pending rows and remember their IDs.
-- The single UPDATE both flips 0 -> 2 (claim) and captures the exact
-- rows via OUTPUT, under one lock. A concurrent cycle's "WHERE
-- BackupDone = 0" can no longer see these rows.
-- -------------------------------------------------------------
DECLARE @claimed TABLE (EventId BIGINT PRIMARY KEY, TableNames NVARCHAR(MAX));

UPDATE dbo.BackupOutbox
SET    BackupDone  = 2,                       -- claimed / in-progress
       ModifiedUtc = SYSUTCDATETIME(),
       Attempts    = Attempts + 1
OUTPUT inserted.EventId, inserted.TableNames INTO @claimed
WHERE  BackupDone = 0;

-- If nothing was claimed, the cycle ends here (consumer sleeps X min).

-- -------------------------------------------------------------
-- STEP 2: Distinct set of tables across the claimed rows.
-- Each TableNames value is a JSON array; shred and de-duplicate so
-- each table is snapshotted exactly once no matter how many rows
-- (SP runs) referenced it this cycle.
-- -------------------------------------------------------------
SELECT DISTINCT j.[value] AS TableName
FROM   @claimed c
CROSS APPLY OPENJSON(c.TableNames) j
ORDER BY TableName;

-- -------------------------------------------------------------
-- STEP 3 (in the consumer, not SQL): for each distinct TableName,
-- full-snapshot from SQL Server -> staging -> atomic swap in PostgreSQL.
-- -------------------------------------------------------------

-- -------------------------------------------------------------
-- STEP 4a: On success, complete ONLY the claimed IDs (2 -> 1).
-- Rows that arrived at 0 during steps 2-3 are untouched.
-- -------------------------------------------------------------
UPDATE dbo.BackupOutbox
SET    BackupDone  = 1,
       ModifiedUtc = SYSUTCDATETIME()
WHERE  EventId IN (SELECT EventId FROM @claimed);

-- -------------------------------------------------------------
-- STEP 4b: On handled failure, release the claim (2 -> 0) so the
-- next cycle retries. Full-snapshot is idempotent, so retry is safe.
--     UPDATE dbo.BackupOutbox
--     SET BackupDone = 0, ModifiedUtc = SYSUTCDATETIME(), LastError = @err
--     WHERE EventId IN (SELECT EventId FROM @claimed);
--
-- REAPER (run at the start of each cycle, before STEP 1): reclaim rows
-- stuck at 2 from a hard crash where 4b never ran.
--     UPDATE dbo.BackupOutbox
--     SET BackupDone = 0, ModifiedUtc = SYSUTCDATETIME()
--     WHERE BackupDone = 2
--       AND ModifiedUtc < DATEADD(MINUTE, -15, SYSUTCDATETIME());
-- -------------------------------------------------------------
