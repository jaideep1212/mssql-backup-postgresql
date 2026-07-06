# mssql-backup-postgresql

Mirrors selected SQL Server tables into PostgreSQL on a Raspberry Pi. When a
stored procedure writes data, it records the fact in an outbox table; the laptop
notices pending work, briefly opens a firewall port, and triggers the Pi to pull
a fresh snapshot of the affected tables into PostgreSQL — then closes the port.

Encrypted columns (Fernet) are carried as raw bytes and never decrypted in
transit, so the mirror holds the same encrypted values as the source; a separate
downstream (or the included verification tool) decrypts them with the key.

## Architecture

```
SQL Server (on the laptop)
  stored procedures  -> INSERT a row into dbo.BackupOutbox listing tables written
                        (inside their own transaction, before COMMIT)

Laptop (scheduled task, every few minutes)
  1. reads BackupOutbox locally (shared memory - no network/port needed)
  2. if work is pending: opens the SQL Server firewall port ("allow-pi")
  3. SSHes the Pi to run ONE replication cycle, and waits for it
  4. closes the firewall port

Raspberry Pi (replicator container, runs idle until triggered)
  claim pending outbox rows -> coalesce to a distinct table set
    -> full-snapshot each table from SQL Server into PostgreSQL
       (staging table + atomic TRUNCATE/reload swap)
    -> mark the claimed outbox rows done
```

No message broker and no Pi-side timer: the laptop is the sole scheduler,
because only it can read `BackupOutbox` without opening the firewall. A cycle
runs on demand via `docker exec replicator-test python -m replicator.run_once`.

Two lanes, pinned end to end via `LANE` (TEST now, PROD later):
TEST = `LocalTestDB` -> `household_test`; PROD = `LocalProdDB` -> `household_prod`.

## Replication model

- **Full-snapshot replace**, not delta: each cycle reads the whole table and
  swaps it into PostgreSQL atomically (staging table, then TRUNCATE + reload in
  one transaction). This handles hard-deletes for free.
- **Outbox, not triggers**: SPs append a row to `dbo.BackupOutbox` naming the
  tables they wrote. Per cycle, all pending rows are claimed and their table
  lists are de-duplicated, so a burst of writes to one table causes one snapshot.
- **Keys carried verbatim** (Option A): the PostgreSQL `id` is a plain `bigint`
  holding the SQL Server ID as-is. The mirror is FK-free so plain TRUNCATE works.
- **Encrypted/hashed columns** (`varbinary`) are carried as raw `bytea`, never
  decoded. Decryption is a downstream concern.

## Layout

- `mssql/`      SQL Server objects: `BackupOutbox` table, permissions (`svcreader`),
               instrumented stored procedures, reference cycle SQL.
- `postgres/`   PostgreSQL schema (11 FK-free mirror tables) and permissions
               (`svcbackup`). `postgres/test/` holds the type-test table.
- `src/consumer/replicator/`  the replicator package: config, db, mapping,
               outbox, snapshot, `main` (loop) and `run_once` (single cycle).
- `pi/`        Raspberry Pi deployment: `docker-compose.yml` + `.env.example`.
- `home/`      laptop side: `Backup-PortGate.ps1` (outbox check -> open port ->
               SSH-trigger -> close) and `SETUP.md` (SSH key + Task Scheduler).
- `tools/`     manual utilities: `verify_decrypt_export.py` (decrypt the mirror
               to CSV), `seed_testtbl.py`, and their runner scripts.
- `docs/`      runbooks: `END_TO_END_TEST.md`, `TESTTBL_FLOW.md`.
- `jenkins/`   `Jenkinsfile` (CI: pytest on every PR; build + deploy on main).
- `shared/`    the authoritative table/field mapping.

## Deploy

**SQL Server** (run via sqlcmd/SSMS against `LocalTestDB`):
1. `mssql/01_backup_outbox_table.sql` — creates `dbo.BackupOutbox`.
2. `mssql/permissions.sql` — the `svcreader` login (needs Mixed Mode auth).
3. Instrumented stored procedures — each INSERTs one outbox row before COMMIT.

`mssql/02_consumer_cycle.reference.sql` is REFERENCE ONLY (documents the exact
claim -> distinct -> snapshot -> complete SQL); it is not deployed.

**PostgreSQL** (on the Pi, against `household_test`):
1. `postgres/schema.sql` — the 11 mirror tables.
2. `postgres/permissions.sql` — grants `svcbackup` USAGE + **CREATE** on schema
   `public` (needed for the staging tables) and SELECT/INSERT/TRUNCATE on tables.

**Replicator** (on the Pi): built locally by Jenkins (native arm64, no registry).
The container runs idle; `pi/docker-compose.yml` joins the existing `postgres`
container's network. Config comes from a `.env` next to the compose (never
committed). Per-lane suffixed vars: `MSSQL_*_TEST`, `PG_*_TEST`, etc.

**Laptop**: copy `Backup-PortGate.ps1` to a stable path (e.g. `C:\Scripts\`),
set up the SSH key to the Pi and the scheduled task per `home/SETUP.md`. The
scheduled task's interval is the whole system's cadence.

## CI

`jenkins/Jenkinsfile` runs on Jenkins on the Pi. On every PR it runs the unit
tests (pytest, in a throwaway container) as a merge gate; on `main` it builds the
image locally and redeploys the container. SQL/schema deploys are manual.

## Verifying the mirror

`tools/verify_decrypt_export.py` (via `tools/run_verify.sh --test`) reads the
replicated tables from PostgreSQL, decrypts the Fernet columns with the key from
`ENCRYPTION_KEY_TEST`, hex-encodes the hash columns, and writes CSVs. Because
Fernet is authenticated, successful decryption proves the encrypted bytes
replicated intact — i.e. the mirror is byte-perfect and downstream-usable.

`docs/TESTTBL_FLOW.md` describes a small all-types test table (`TestTbl` ->
`test_tbl`) that exercises every mapped data type (text, hash, encrypted blob,
datetime, decimal, int, bool) plus the encrypted round-trip, for fast checks.

## Notes

- The laptop's IP is currently used directly by the replicator (`MSSQL_HOST`);
  reserve it via DHCP so it stays stable.
- The Fernet key lives only in the verification tool's `.env` on the Pi — the
  replicator never holds it and never decrypts.
