# TestTbl -> test_tbl : all-types replication test

A small, fast test that exercises EVERY data type the replicator maps (text,
hash, encrypted blob, datetime, decimal, int, bool) on a tiny table instead of
the big real ones. Also proves the Fernet round-trip: a known plaintext is
encrypted, replicated, and must decrypt back to the same string downstream.

Legend:  [SQL] SQL Server (SSMS or sqlcmd)   [PI] Raspberry Pi   [PG] postgres container

---

## One-time setup

**1. [SQL] Create the SQL Server test table** (LocalTestDB):
```
-- run mssql/create_TestTbl.sql
```
Creates dbo.TestTbl (all 7 types) and grants SELECT to svcreader.

**2. [PG] Create the Postgres mirror** (household_test):
```bash
docker exec -i postgres psql -U admin -d household_test < postgres/create_test_tbl.sql
```
Creates public.test_tbl and grants to svcbackup.

**3. Add the mapping entry.** Merge mapping_entry_TestTbl.json's "dbo.TestTbl"
block into the replicator's table_mapping.json (same structure as the other
tables), then rebuild/redeploy the replicator image so it knows the new table.

**4. The verify tool already knows test_tbl** (enc_field -> decrypt,
hash_field -> hex) - no change needed, just use the latest verify_decrypt_export.py.

---

## Each test run

**5. Seed known data** (encrypts known plaintext with the Fernet key):
```bash
# needs the SQL Server port open + ENCRYPTION_KEY_TEST + MSSQL_*_TEST env
python tools/seed_testtbl.py
```
This inserts rows whose EncField is Fernet(key, "Hello World"), etc., and writes
expected_testtbl.json (the plaintext each enc_field must decrypt back to).

**6. [SQL] Queue an outbox row for TestTbl** so the replicator picks it up:
```sql
INSERT INTO dbo.BackupOutbox (TableNames, BackupDone, CreatedUtc)
VALUES (N'["dbo.TestTbl"]', 0, SYSUTCDATETIME());
```

**7. Trigger a cycle** (laptop port-gate script, or directly on the Pi with the
port open):
```bash
docker exec replicator-test python -m replicator.run_once
```

**8. [PG] Confirm the rows landed and types look right:**
```bash
docker exec postgres psql -U admin -d household_test -c "SELECT id, text_field, decimal_field, int_field, bool_field, date_field FROM test_tbl ORDER BY id;"
```
Check: decimal keeps 4 dp exactly, bool shows t/f, datetime has sub-second part,
unicode text intact.

**9. Verify the encrypted round-trip** (decrypt test_tbl.enc_field):
```bash
cd tools && ./run_verify.sh --test
```
This writes test_tbl_decrypted.csv. The enc_field column should show the ORIGINAL
plaintext ("Hello World", "Björk Ödegård åäö", ...). Compare against
expected_testtbl.json - they must match.

---

## Pass criteria

1. test_tbl row count == TestTbl row count (including the NULL row).
2. text_field: unicode preserved.
3. hash_field (hex) == the sha512 hex from the seed (expected_testtbl.json).
4. enc_field decrypts to the exact original plaintext (the key proof).
5. decimal_field: exact 4-dp value, no float drift.
6. date_field: datetime2 precision preserved.
7. bool_field: 1->t, 0->f.
8. the NULL row: all columns NULL / empty, no crash.

If all hold, every type maps correctly AND encrypted data survives byte-perfect
and decrypts downstream - on a table you can re-run in seconds.

---

## Type mapping reference

| SQL Server      | PostgreSQL      | verify handling         |
|-----------------|-----------------|-------------------------|
| INT IDENTITY    | bigint          | as-is                   |
| NVARCHAR(200)   | text            | as-is (unicode)         |
| VARBINARY(64)   | bytea           | hex-encode              |
| VARBINARY(MAX)  | bytea           | Fernet-decrypt          |
| DATETIME2       | timestamp       | as-is                   |
| DECIMAL(18,4)   | numeric(18,4)   | as-is (exact)           |
| INT             | integer         | as-is                   |
| BIT             | boolean         | as-is (t/f)             |
