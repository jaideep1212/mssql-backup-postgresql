# End-to-End Test Runbook

Proves the full chain works before automating anything:

    instrumented SP writes a table  ->  BackupOutbox row appears (SQL Server)
      ->  laptop script sees it, opens firewall, SSH-triggers the Pi
      ->  Pi replicator reads the table, snapshots it into PostgreSQL
      ->  outbox row marked done, firewall closed
      ->  PostgreSQL mirror matches SQL Server (binary intact)

Test each link in order. If a step fails, you know exactly which link broke.

Legend:  [LAPTOP] run on the Windows laptop   [PI] run on the Raspberry Pi
         [SSMS] run in SQL Server Mgmt Studio against LocalTestDB

---

## Stage 0 — Preconditions (verify once)

**[PI] Postgres is up and has the schema + role:**
```bash
docker exec -it postgres psql -U svcbackup -d household_test -c "\dt"
```
Expect to see the 11 mirror tables (dim_accounts, dim_users, ... fact_stock_transactions).
If you get a login error, the svcbackup role/permissions aren't applied — run postgres/permissions.sql.

**[SSMS] SQL Server has the outbox + the login works:**
```sql
SELECT TOP 1 * FROM dbo.BackupOutbox;          -- table exists (may be empty)
-- confirm the reader login can see a table it will replicate:
EXECUTE AS LOGIN = 'svcreader';
SELECT TOP 1 * FROM dbo.DimUsers;              -- should succeed
REVERT;
```

**[LAPTOP] The port-gate script and SSH work** (already verified, re-confirm):
```powershell
ssh -o BatchMode=yes InTheEnd "docker ps --format '{{.Names}}'"
```
Expect to see `replicator-test` (and postgres, nginx, jenkins) WITHOUT a password prompt.

---

## Stage 1 — Bring up the replicator container (idle)

**[PI] Build the image and start the idle container:**
```bash
cd ~/replicator                 # your working dir with docker-compose.yml + .env
# build (Jenkins will do this later; by hand for now, from the repo checkout):
docker build -t mssql-backup-replicator:latest /path/to/repo/checkout
# start it (idle - it just sleeps, waiting for triggers):
docker compose up -d
docker ps --format '{{.Names}}\t{{.Status}}' | grep replicator-test
```
Expect `replicator-test  Up ...`. The container is running but doing nothing yet — that is correct.

**[PI] Sanity-check the container can even run the module:**
```bash
docker exec replicator-test python -c "import replicator.run_once; print('module OK')"
```
Expect `module OK`. If this fails, the image/PYTHONPATH is wrong — fix before continuing.

---

## Stage 2 — Prove connectivity from inside the container

Before triggering a real cycle, confirm the container can reach BOTH databases.

**[PI] Postgres reachability (should always work - same Docker network):**
```bash
docker exec replicator-test python -c "
import os, psycopg
c = psycopg.connect(host='postgres', dbname=os.environ['PG_DB_TEST'],
                    user=os.environ['PG_USER'], password=os.environ['PG_PASSWORD_TEST'])
print('postgres OK'); c.close()
"
```

**[PI] SQL Server reachability — THIS NEEDS THE FIREWALL PORT OPEN.**
Because the port is normally closed, open it manually just for this test:

  [LAPTOP] temporarily open the port:
```powershell
Enable-NetFirewallRule -DisplayName "SQL Server 1433"
```
  [PI] then test the SQL Server connection from the container:
```bash
docker exec replicator-test python -c "
import os, pyodbc
from replicator.config import Config
cfg = Config()
c = pyodbc.connect(cfg.mssql_odbc_connstr()); 
print('sqlserver OK'); c.close()
"
```
  [LAPTOP] close it again:
```powershell
Disable-NetFirewallRule -DisplayName "SQL Server 1433"
```
Expect `sqlserver OK`. A failure here is almost always: firewall still closed, wrong
MSSQL_HOST/port in .env, or svcreader password mismatch.

---

## Stage 3 — Create a change to replicate

**[SSMS] Run an instrumented SP so it writes a table AND inserts an outbox row.**
Use whatever real input your SP expects; the point is to make it do work. Example
shape (adjust to your actual SP + data):
```sql
EXEC dbo.sp_UpsertUsers @users_json = N'[{"UserNameHash":"...", "Gender":"M", ...}]';
```
Then confirm the outbox got a pending row:
```sql
SELECT EventId, TableNames, BackupDone, CreatedUtc
FROM dbo.BackupOutbox
WHERE BackupDone = 0
ORDER BY EventId DESC;
```
Expect at least one row with BackupDone = 0 and TableNames listing the table(s) the SP wrote.

**[SSMS] Record the source truth to compare against later:**
```sql
SELECT COUNT(*) AS src_rows FROM dbo.DimUsers;
-- capture one row's binary column to compare byte-for-byte after replication:
SELECT TOP 1 ID, CONVERT(VARCHAR(MAX), UserNameHash, 1) AS hash_hex
FROM dbo.DimUsers ORDER BY ID;
```
Write down src_rows and the hash_hex value.

---

## Stage 4 — Trigger one cycle the real way (via the script)

**[LAPTOP] Run the port-gate script by hand (elevated PowerShell):**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Backup-PortGate.ps1"
```
Watch the output. Expected sequence:
- "N pending row(s) - opening port and triggering the Pi."
- "PORT OPENED"
- "triggering: ssh ... run_once"
- (the Pi runs one cycle; the run_once logs stream back over SSH)
- "Pi cycle completed cleanly."
- "PORT CLOSED"

If it instead says "No pending work", Stage 3 didn't create an outbox row — recheck.

---

## Stage 5 — Verify the outbox was completed

**[SSMS] The pending row(s) should now be done (BackupDone = 1):**
```sql
SELECT EventId, TableNames, BackupDone, ModifiedUtc
FROM dbo.BackupOutbox
ORDER BY EventId DESC;
```
Expect the row(s) from Stage 3 now show BackupDone = 1. If they are still 0 or stuck
at 2, the cycle failed — check the Pi:  docker logs replicator-test  (or the SSH error
log on the laptop: %TEMP%\portgate_ssh_err.log).

---

## Stage 6 — Verify PostgreSQL matches SQL Server (the real proof)

**[PI] Row count matches the source:**
```bash
docker exec postgres psql -U svcbackup -d household_test -c "SELECT COUNT(*) FROM dim_users;"
```
Expect the same number as src_rows from Stage 3.

**[PI] Binary column came through byte-for-byte:**
```bash
docker exec postgres psql -U svcbackup -d household_test -c \
  "SELECT id, encode(user_name_hash, 'hex') AS hash_hex FROM dim_users ORDER BY id LIMIT 1;"
```
Compare hash_hex against the value you recorded in Stage 3. THEY MUST MATCH EXACTLY.
(SQL Server's CONVERT(..,1) prefixes with '0x'; Postgres encode(...,'hex') does not —
so ignore the leading 0x and compare the hex digits.) A match proves VARBINARY -> BYTEA
carried the encrypted/hashed bytes with zero corruption.

**[PI] IDs match the source (Option A verification):**
```bash
docker exec postgres psql -U svcbackup -d household_test -c "SELECT MIN(id), MAX(id) FROM dim_users;"
```
Expect the same min/max IDs as SQL Server — proving Postgres carried the source IDs
verbatim rather than generating its own.

---

## Stage 7 — Idempotency / no-work check

**[LAPTOP] Run the script again immediately (nothing new changed):**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Backup-PortGate.ps1"
```
Expect "No pending work - leaving port CLOSED." and the firewall rule stays DISABLED.
This proves the gate only opens when there is genuine work.

---

## Pass criteria (all must hold)

1. Stage 4 opened the port, triggered the Pi, and closed the port.
2. Stage 5 outbox row went 0 -> 1.
3. Stage 6 Postgres row count == SQL Server row count.
4. Stage 6 binary hash matches byte-for-byte.
5. Stage 6 IDs match the source (no renumbering).
6. Stage 7 with no work, the port never opened.

If all six hold, the full pipeline works end to end and is safe to automate with Jenkins.

---

## Quick failure map

| Symptom | Likely cause |
|---|---|
| SSH asks for password | key not in Pi authorized_keys / wrong task user |
| "no such container" on trigger | replicator-test not up (Stage 1) |
| sqlserver connection fails | firewall closed, wrong MSSQL_HOST/port, svcreader pwd |
| postgres connection fails | svcbackup pwd, wrong PG_DB, schema not loaded |
| outbox stuck at 2 | cycle crashed mid-run; check docker logs replicator-test |
| row counts differ | snapshot read a different DB, or SP wrote a table not in the outbox message |
| hash mismatch | (should not happen) binary corruption — capture and report |
