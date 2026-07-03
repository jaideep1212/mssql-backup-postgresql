USE [LocalTestDB]
GO

/****** Object:  StoredProcedure [dbo].[sp_UpsertUserAliases]    Script Date: 7/3/2026 12:52:22 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Stored Procedure: sp_UpsertUserAliases
-- Description: Upsert user aliases using NameKey lookup
--              Input format: [{"NameKey": "...", "AliasNames": ["alias1", "alias2", ...]}, ...]
-- Steps:
--   1. Read NameKey from each dictionary in JSON input
--   2. Resolve NameKey to UserID from DimUsers
--   3. For each AliasName, insert record in FactAliases (RecordType='users', RecordId=UserID)
--   4. Commit all insertions in single transaction
--   5. Return full FactAliases dump for cache refresh
-- =============================================

CREATE   PROCEDURE [dbo].[sp_UpsertUserAliases]
    @aliases_map NVARCHAR(MAX)
AS
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        SET NOCOUNT ON;

        -- Track inserted records
        DECLARE @AffectedIDs TABLE (ID INT);

        -- Validate input
        IF @aliases_map IS NULL
           OR LTRIM(RTRIM(@aliases_map)) = ''
           OR ISJSON(@aliases_map) = 0
        BEGIN
            RAISERROR('Invalid input: @aliases_map must be valid JSON array', 16, 1);
        END

        -- STEP 1 & 2: Parse JSON and resolve NameKey → UserID
        ;WITH AliasInput AS (
            SELECT
                CONVERT(VARBINARY(32), JSON_VALUE([value], '$.UserNameHash'), 2) AS UserNameHash,
                JSON_VALUE([value], '$.AliasName') AS AliasName
            FROM OPENJSON(@aliases_map)
            WHERE JSON_VALUE([value], '$.UserNameHash') IS NOT NULL
              AND JSON_VALUE([value], '$.AliasName') IS NOT NULL
              AND NULLIF(LTRIM(RTRIM(JSON_VALUE([value], '$.AliasName'))), '') IS NOT NULL
        ),
        ResolvedAliases AS (
            SELECT
                DU.ID AS UserID,
                AI.AliasName,
                ROW_NUMBER() OVER (
                    PARTITION BY DU.ID, AI.AliasName
                    ORDER BY (SELECT NULL)
                ) AS rn
            FROM AliasInput AI
            INNER JOIN dbo.DimUsers DU ON DU.UserNameHash = AI.UserNameHash
        )
        -- STEP 3: Insert aliases with RecordType='users' and resolved UserID
        INSERT INTO dbo.FactAliases (RecordType, RecordId, AliasName, CreatedDate, ModifiedDate)
        OUTPUT INSERTED.ID INTO @AffectedIDs
        SELECT
            'users' AS RecordType,
            UserID,
            CAST(NULLIF(LTRIM(RTRIM(AliasName)), '') AS VARBINARY(MAX)) AS AliasName,
            GETDATE(),
            GETDATE()
        FROM ResolvedAliases
        WHERE rn = 1  -- Skip duplicates
          AND NOT EXISTS (
              SELECT 1 FROM dbo.FactAliases DA
              WHERE DA.RecordId = ResolvedAliases.UserID
                AND DA.RecordType = 'users'
                AND DA.AliasName = CAST(NULLIF(LTRIM(RTRIM(ResolvedAliases.AliasName)), '') AS VARBINARY(MAX))
          );

        -- ========================================
        -- STEP 3: Emit backup signal into the outbox
        -- ========================================
        INSERT INTO dbo.BackupOutbox (TableNames)
        VALUES (N'["dbo.FactAliases"]');

        -- STEP 4: Commit transaction
        COMMIT TRAN;

        -- RESULT SET 1: Summary of affected records
        SELECT (SELECT COUNT(*) FROM @AffectedIDs) AS AliasInsertCount;

        -- RESULT SET 2: Return full FactAliases dump for cache refresh
        SELECT
            ID,
            RecordType,
            RecordId,
            AliasName,
            CreatedDate,
            ModifiedDate
        FROM dbo.FactAliases
        ORDER BY ID;

    END TRY
    BEGIN CATCH
        -- Rollback on error
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();

        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END
GO


