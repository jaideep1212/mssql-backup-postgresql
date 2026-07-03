USE [LocalTestDB]
GO

/****** Object:  StoredProcedure [dbo].[sp_UpsertUsers]    Script Date: 7/3/2026 11:52:27 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



-- ========================================
-- sp_UpsertUsers.sql (Batch Processing)
-- Purpose: Atomic batch upsert workflow for users and sensitive data
-- Workflow:
--   1. Accept JSON array of all user records
--   2. For each record: NameKey matching, INSERT/UPDATE DimUsers/DimUsers_S
--   3. COMMIT after all user records processed
--   4. Return dumps of DimUsers and DimUsers_S
-- Note: Alias operations are now handled by sp_UpsertUserAliases (separate procedure)
-- ========================================

CREATE OR ALTER PROCEDURE [dbo].[sp_UpsertUsers]
    @json_array NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- ========================================
        -- STEP 1: Parse and Validate Input JSON Array
        -- ========================================
        
        -- Parse input JSON array into temp table
        CREATE TABLE #SourceData (
            RowNum INT IDENTITY(1,1),
            UserNameHash NVARCHAR(500),
            FirstName NVARCHAR(MAX),                 -- Encrypted in DimUsers_S
            LastName NVARCHAR(MAX),                  -- Encrypted in DimUsers_S
            Gender VARCHAR(1),
            Age INT,
            BirthDate NVARCHAR(MAX),                 -- Encrypted in DimUsers_S
            BirthCity NVARCHAR(MAX),                 -- Encrypted in DimUsers_S
            BirthCountry NVARCHAR(MAX),              -- Encrypted in DimUsers_S
            MaritalStatus VARCHAR(1),
            MarriageDate NVARCHAR(MAX),              -- Encrypted in DimUsers_S
            ExpiredDate NVARCHAR(MAX),               -- Encrypted in DimUsers_S
            IsExpired BIT,
            SpouseId INT,
            FatherId INT,
            MotherId INT,
            ContactEmailId NVARCHAR(MAX),            -- Encrypted in DimUsers_S
            ContactMobileNo NVARCHAR(MAX),           -- Encrypted in DimUsers_S
            ContactPhoneNo NVARCHAR(MAX),            -- Encrypted in DimUsers_S
            WorkEmailId NVARCHAR(MAX),               -- Encrypted in DimUsers_S
            WorkMobileNo NVARCHAR(MAX),              -- Encrypted in DimUsers_S
            WorkPhoneNo NVARCHAR(MAX),               -- Encrypted in DimUsers_S
            CurrentAddressLine1 NVARCHAR(MAX),       -- Encrypted in DimUsers_S
            CurrentAddressLine2 NVARCHAR(MAX),       -- Encrypted in DimUsers_S
            CurrentCity NVARCHAR(MAX),               -- Encrypted in DimUsers_S
            CurrentPostCode NVARCHAR(MAX),           -- Encrypted in DimUsers_S
            CurrentCountry NVARCHAR(MAX),            -- Encrypted in DimUsers_S
            PermanentAddressLine1 NVARCHAR(MAX),     -- Encrypted in DimUsers_S
            PermanentAddressLine2 NVARCHAR(MAX),     -- Encrypted in DimUsers_S
            PermanentCity NVARCHAR(MAX),             -- Encrypted in DimUsers_S
            PermanentPostCode NVARCHAR(MAX),         -- Encrypted in DimUsers_S
            PermanentCountry NVARCHAR(MAX),          -- Encrypted in DimUsers_S
            PAN NVARCHAR(MAX),                       -- Encrypted in DimUsers_S
            Aadhar NVARCHAR(MAX),                    -- Encrypted in DimUsers_S
            TIN NVARCHAR(MAX)                        -- Encrypted in DimUsers_S
        );

        INSERT INTO #SourceData (
            UserNameHash, FirstName, LastName, Gender, Age,
            BirthDate, BirthCity, BirthCountry, MaritalStatus, MarriageDate, ExpiredDate, IsExpired,
            SpouseId, FatherId, MotherId,
            ContactEmailId, ContactMobileNo, ContactPhoneNo,
            WorkEmailId, WorkMobileNo, WorkPhoneNo,
            CurrentAddressLine1, CurrentAddressLine2, CurrentCity, CurrentPostCode, CurrentCountry,
            PermanentAddressLine1, PermanentAddressLine2, PermanentCity, PermanentPostCode, PermanentCountry,
            PAN, Aadhar, TIN
        )
        SELECT
            JSON_VALUE(value, '$.UserNameHash'),
            JSON_VALUE(value, '$.FirstName'),
            JSON_VALUE(value, '$.LastName'),
            JSON_VALUE(value, '$.Gender'),
            JSON_VALUE(value, '$.Age'),
            JSON_VALUE(value, '$.BirthDate'),
            JSON_VALUE(value, '$.BirthCity'),
            JSON_VALUE(value, '$.BirthCountry'),
            JSON_VALUE(value, '$.MaritalStatus'),
            JSON_VALUE(value, '$.MarriageDate'),
            JSON_VALUE(value, '$.ExpiredDate'),
            JSON_VALUE(value, '$.IsExpired'),
            JSON_VALUE(value, '$.SpouseId'),
            JSON_VALUE(value, '$.FatherId'),
            JSON_VALUE(value, '$.MotherId'),
            JSON_VALUE(value, '$.ContactEmailId'),
            JSON_VALUE(value, '$.ContactMobileNo'),
            JSON_VALUE(value, '$.ContactPhoneNo'),
            JSON_VALUE(value, '$.WorkEmailId'),
            JSON_VALUE(value, '$.WorkMobileNo'),
            JSON_VALUE(value, '$.WorkPhoneNo'),
            JSON_VALUE(value, '$.CurrentAddressLine1'),
            JSON_VALUE(value, '$.CurrentAddressLine2'),
            JSON_VALUE(value, '$.CurrentCity'),
            JSON_VALUE(value, '$.CurrentPostCode'),
            JSON_VALUE(value, '$.CurrentCountry'),
            JSON_VALUE(value, '$.PermanentAddressLine1'),
            JSON_VALUE(value, '$.PermanentAddressLine2'),
            JSON_VALUE(value, '$.PermanentCity'),
            JSON_VALUE(value, '$.PermanentPostCode'),
            JSON_VALUE(value, '$.PermanentCountry'),
            JSON_VALUE(value, '$.PAN'),
            JSON_VALUE(value, '$.Aadhar'),
            JSON_VALUE(value, '$.TIN')
        FROM OPENJSON(@json_array) records
        WHERE JSON_VALUE(value, '$.UserNameHash') IS NOT NULL;

        -- Log validation
        DECLARE @total_records INT = (SELECT COUNT(*) FROM #SourceData);
        PRINT '[sp_UpsertUsers] Total records parsed: ' + CAST(@total_records AS NVARCHAR(10));

        -- ========================================
        -- STEP 2: Match All Records - NameKey Against Existing Users
        -- ========================================

        CREATE TABLE #MatchedUsers (
            RowNum INT,
            UserNameHash NVARCHAR(500),
            MatchedUserID INT,  -- NULL if no match (new user)
            FirstName NVARCHAR(MAX),
            LastName NVARCHAR(MAX),
            Gender VARCHAR(1),
            Age INT,
            BirthDate NVARCHAR(MAX),
            BirthCity NVARCHAR(MAX),
            BirthCountry NVARCHAR(MAX),
            MaritalStatus VARCHAR(1),
            MarriageDate NVARCHAR(MAX),
            ExpiredDate NVARCHAR(MAX),
            IsExpired BIT,
            SpouseId INT,
            FatherId INT,
            MotherId INT,
            ContactEmailId NVARCHAR(MAX),
            ContactMobileNo NVARCHAR(MAX),
            ContactPhoneNo NVARCHAR(MAX),
            WorkEmailId NVARCHAR(MAX),
            WorkMobileNo NVARCHAR(MAX),
            WorkPhoneNo NVARCHAR(MAX),
            CurrentAddressLine1 NVARCHAR(MAX),
            CurrentAddressLine2 NVARCHAR(MAX),
            CurrentCity NVARCHAR(MAX),
            CurrentPostCode NVARCHAR(MAX),
            CurrentCountry NVARCHAR(MAX),
            PermanentAddressLine1 NVARCHAR(MAX),
            PermanentAddressLine2 NVARCHAR(MAX),
            PermanentCity NVARCHAR(MAX),
            PermanentPostCode NVARCHAR(MAX),
            PermanentCountry NVARCHAR(MAX),
            PAN NVARCHAR(MAX),
            Aadhar NVARCHAR(MAX),
            TIN NVARCHAR(MAX)
        );

        INSERT INTO #MatchedUsers
        SELECT
            SD.RowNum,
            SD.UserNameHash,
            DU.ID,  -- MatchedUserID (NULL if no match)
            SD.FirstName,
            SD.LastName,
            SD.Gender,
            SD.Age,
            SD.BirthDate,
            SD.BirthCity,
            SD.BirthCountry,
            SD.MaritalStatus,
            SD.MarriageDate,
            SD.ExpiredDate,
            SD.IsExpired,
            SD.SpouseId,
            SD.FatherId,
            SD.MotherId,
            SD.ContactEmailId,
            SD.ContactMobileNo,
            SD.ContactPhoneNo,
            SD.WorkEmailId,
            SD.WorkMobileNo,
            SD.WorkPhoneNo,
            SD.CurrentAddressLine1,
            SD.CurrentAddressLine2,
            SD.CurrentCity,
            SD.CurrentPostCode,
            SD.CurrentCountry,
            SD.PermanentAddressLine1,
            SD.PermanentAddressLine2,
            SD.PermanentCity,
            SD.PermanentPostCode,
            SD.PermanentCountry,
            SD.PAN,
            SD.Aadhar,
            SD.TIN
        FROM #SourceData SD
        LEFT JOIN dbo.DimUsers DU
            ON DU.UserNameHash = CONVERT(VARBINARY(64), SD.UserNameHash, 2);

        -- STEP 3: Begin Transaction for Batch Operations
        -- ========================================
        BEGIN TRAN;

        -- Track INSERT and UPDATE operations for summary
        DECLARE @AffectedIDs TABLE (ID INT, Action NVARCHAR(10));
        DECLARE @UpdateCount INT = 0;
        DECLARE @InsertCount INT = 0;

        -- ========================================
        -- STEP 4: Batch UPDATE Existing Users in DimUsers
        -- ========================================

        UPDATE dbo.DimUsers
        SET
            Gender = NULLIF(MU.Gender, ''),
            Age = MU.Age,
            MaritalStatus = NULLIF(MU.MaritalStatus, ''),
            IsExpired = MU.IsExpired,
            SpouseId = MU.SpouseId,
            FatherId = MU.FatherId,
            MotherId = MU.MotherId,
            ModifiedDate = GETDATE()
        FROM #MatchedUsers MU
        INNER JOIN dbo.DimUsers DU ON DU.ID = MU.MatchedUserID
        WHERE MU.MatchedUserID IS NOT NULL;

        SET @UpdateCount = @@ROWCOUNT;

        -- ========================================
        -- STEP 5: Batch UPDATE Existing Users in DimUsers_S (Sensitive Fields)
        -- ========================================

        UPDATE dbo.DimUsers_S
        SET
            FirstName = CAST(MU.FirstName AS VARBINARY(MAX)),
            LastName = CAST(MU.LastName AS VARBINARY(MAX)),
            BirthDate = CAST(MU.BirthDate AS VARBINARY(MAX)),
            BirthCity = CAST(MU.BirthCity AS VARBINARY(MAX)),
            BirthCountry = CAST(MU.BirthCountry AS VARBINARY(MAX)),
            MarriageDate = CAST(MU.MarriageDate AS VARBINARY(MAX)),
            ExpiredDate = CAST(MU.ExpiredDate AS VARBINARY(MAX)),
            ContactEmailId = CAST(MU.ContactEmailId AS VARBINARY(MAX)),
            ContactMobileNo = CAST(MU.ContactMobileNo AS VARBINARY(MAX)),
            ContactPhoneNo = CAST(MU.ContactPhoneNo AS VARBINARY(MAX)),
            WorkEmailId = CAST(MU.WorkEmailId AS VARBINARY(MAX)),
            WorkMobileNo = CAST(MU.WorkMobileNo AS VARBINARY(MAX)),
            WorkPhoneNo = CAST(MU.WorkPhoneNo AS VARBINARY(MAX)),
            CurrentAddressLine1 = CAST(MU.CurrentAddressLine1 AS VARBINARY(MAX)),
            CurrentAddressLine2 = CAST(MU.CurrentAddressLine2 AS VARBINARY(MAX)),
            CurrentCity = CAST(MU.CurrentCity AS VARBINARY(MAX)),
            CurrentPostCode = CAST(MU.CurrentPostCode AS VARBINARY(MAX)),
            CurrentCountry = CAST(MU.CurrentCountry AS VARBINARY(MAX)),
            PermanentAddressLine1 = CAST(MU.PermanentAddressLine1 AS VARBINARY(MAX)),
            PermanentAddressLine2 = CAST(MU.PermanentAddressLine2 AS VARBINARY(MAX)),
            PermanentCity = CAST(MU.PermanentCity AS VARBINARY(MAX)),
            PermanentPostCode = CAST(MU.PermanentPostCode AS VARBINARY(MAX)),
            PermanentCountry = CAST(MU.PermanentCountry AS VARBINARY(MAX)),
            PAN = CAST(MU.PAN AS VARBINARY(MAX)),
            Aadhar = CAST(MU.Aadhar AS VARBINARY(MAX)),
            TIN = CAST(MU.TIN AS VARBINARY(MAX)),
            ModifiedDate = GETDATE()
        FROM #MatchedUsers MU
        INNER JOIN dbo.DimUsers_S DUS ON DUS.UserID = MU.MatchedUserID
        WHERE MU.MatchedUserID IS NOT NULL;

        -- ========================================
        -- STEP 6: Batch INSERT New Users via MERGE
        -- ========================================

        DECLARE @InsertedUsers TABLE (
            RowNum INT,
            UserID INT
        );

        -- Use MERGE to insert new users and capture IDs
        MERGE INTO dbo.DimUsers DU
        USING (
            SELECT MU.*
            FROM #MatchedUsers MU
            WHERE MU.MatchedUserID IS NULL
        ) src
        ON 1 = 0  -- Never match, always insert
        WHEN NOT MATCHED THEN
            INSERT (
                UserNameHash, Gender, Age,
                MaritalStatus, IsExpired, SpouseId, FatherId, MotherId,
                CreatedDate, ModifiedDate
            )
            VALUES (
                CONVERT(VARBINARY(32), src.UserNameHash, 2), src.Gender, src.Age,
                src.MaritalStatus, src.IsExpired,
                src.SpouseId, src.FatherId, src.MotherId,
                GETDATE(), GETDATE()
            )
        OUTPUT src.RowNum, INSERTED.ID
        INTO @InsertedUsers (RowNum, UserID);

        -- ========================================
        -- STEP 7: Batch INSERT Sensitive Data for New Users into DimUsers_S
        -- ========================================

        INSERT INTO dbo.DimUsers_S (
            UserID, FirstName, LastName, BirthDate, BirthCity, BirthCountry,
            MarriageDate, ExpiredDate,
            ContactEmailId, ContactMobileNo, ContactPhoneNo,
            WorkEmailId, WorkMobileNo, WorkPhoneNo,
            CurrentAddressLine1, CurrentAddressLine2, CurrentCity, CurrentPostCode, CurrentCountry,
            PermanentAddressLine1, PermanentAddressLine2, PermanentCity, PermanentPostCode, PermanentCountry,
            PAN, Aadhar, TIN, CreatedDate, ModifiedDate
        )
        SELECT
            IU.UserID,
            CAST(MU.FirstName AS VARBINARY(MAX)),
            CAST(MU.LastName AS VARBINARY(MAX)),
            CAST(MU.BirthDate AS VARBINARY(MAX)),
            CAST(MU.BirthCity AS VARBINARY(MAX)),
            CAST(MU.BirthCountry AS VARBINARY(MAX)),
            CAST(MU.MarriageDate AS VARBINARY(MAX)),
            CAST(MU.ExpiredDate AS VARBINARY(MAX)),
            CAST(MU.ContactEmailId AS VARBINARY(MAX)),
            CAST(MU.ContactMobileNo AS VARBINARY(MAX)),
            CAST(MU.ContactPhoneNo AS VARBINARY(MAX)),
            CAST(MU.WorkEmailId AS VARBINARY(MAX)),
            CAST(MU.WorkMobileNo AS VARBINARY(MAX)),
            CAST(MU.WorkPhoneNo AS VARBINARY(MAX)),
            CAST(MU.CurrentAddressLine1 AS VARBINARY(MAX)),
            CAST(MU.CurrentAddressLine2 AS VARBINARY(MAX)),
            CAST(MU.CurrentCity AS VARBINARY(MAX)),
            CAST(MU.CurrentPostCode AS VARBINARY(MAX)),
            CAST(MU.CurrentCountry AS VARBINARY(MAX)),
            CAST(MU.PermanentAddressLine1 AS VARBINARY(MAX)),
            CAST(MU.PermanentAddressLine2 AS VARBINARY(MAX)),
            CAST(MU.PermanentCity AS VARBINARY(MAX)),
            CAST(MU.PermanentPostCode AS VARBINARY(MAX)),
            CAST(MU.PermanentCountry AS VARBINARY(MAX)),
            CAST(MU.PAN AS VARBINARY(MAX)),
            CAST(MU.Aadhar AS VARBINARY(MAX)),
            CAST(MU.TIN AS VARBINARY(MAX)),
            GETDATE(),
            GETDATE()
        FROM @InsertedUsers IU
        INNER JOIN #MatchedUsers MU
            ON IU.RowNum = MU.RowNum
        WHERE MU.MatchedUserID IS NULL;

        -- ========================================
        -- Emit backup signal into the outbox
        -- ========================================
        INSERT INTO dbo.BackupOutbox (TableNames)
        VALUES (N'["dbo.DimUsers","dbo.DimUsers_S"]');

        -- ========================================
        -- COMMIT AFTER ALL USER RECORDS PROCESSED
        -- ========================================
        COMMIT TRAN;

        -- Note: Alias operations are now handled by separate sp_UpsertUserAliases procedure

        -- ========================================
        -- STEP 8: Return Summary and Full Dumps for Cache Refresh
        -- ========================================

        -- RESULT SET 1: Summary of affected records
        SELECT 
            @UpdateCount AS UpdateCount,
            (SELECT COUNT(*) FROM @InsertedUsers) AS InsertCount;

        -- RESULT SET 2: Return ALL DimUsers records (for complete cache refresh)
        SELECT
            ID, UserNameHash, Gender, Age, MaritalStatus, IsExpired,
            SpouseId, FatherId, MotherId, CreatedDate, ModifiedDate
        FROM dbo.DimUsers
        ORDER BY ID;

        -- RESULT SET 3: Return ALL DimUsers_S records (for complete cache refresh)
        SELECT
            ID, UserID, FirstName, LastName, BirthDate, BirthCity, BirthCountry,
            MarriageDate, CurrentAddressLine1, CurrentAddressLine2, CurrentCity, CurrentPostCode, CurrentCountry,
            PermanentAddressLine1, PermanentAddressLine2, PermanentCity, PermanentPostCode, PermanentCountry,
            ContactEmailId, ContactMobileNo, ContactPhoneNo,
            WorkEmailId, WorkMobileNo, WorkPhoneNo,
            ExpiredDate, PAN, Aadhar, TIN, CreatedDate, ModifiedDate
        FROM dbo.DimUsers_S
        ORDER BY UserID;

        -- ========================================
        -- Cleanup
        -- ========================================
        DROP TABLE IF EXISTS #MatchedUsers;
        DROP TABLE IF EXISTS #SourceData;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        -- Throw error with context
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorNumber INT = ERROR_NUMBER();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();

        -- Map system error numbers to valid user-defined range (50000+)
        IF @ErrorNumber < 50000
            SET @ErrorNumber = 50000;

        THROW @ErrorNumber, @ErrorMessage, @ErrorSeverity;
    END CATCH
END
GO


