# mssql-backup-postgresql

Signals table changes in SQL Server and mirrors those tables into PostgreSQL on a Raspberry Pi.

## Architecture
SQL Server (dirty-flag trigger + BackupDirty table)
  -> relay (polls BackupDirty, publishes to RabbitMQ)
  -> RabbitMQ (per-env vhost on the Pi)
  -> consumer (full-snapshot pull from SQL Server -> PostgreSQL)

Two lanes, pinned end to end: PROD (LocalProdDB -> proddb) and TEST (LocalTestDB -> testdb).

## Layout
- sql/       SQL Server objects (BackupDirty table, seed, triggers)
- relay/     polls BackupDirty and publishes to RabbitMQ
- consumer/  reads full tables from SQL Server, loads into PostgreSQL
- broker/    RabbitMQ topology (definitions.json) + Pi docker-compose
- shared/    message contract
- jenkins/   Jenkinsfile and CI/CD

# sql/ — SQL Server side of the backup signal

Deploy order (idempotent, run via sqlcmd against LocalTestDB, later LocalProdDB):
1. 01_backup_outbox_table.sql   — creates dbo.BackupOutbox (the append-outbox)
2. Instrumented stored procedures — each INSERTs one BackupOutbox row before COMMIT

02_consumer_cycle.reference.sql is REFERENCE ONLY — it documents the exact
claim -> distinct -> snapshot -> complete SQL the Pi consumer runs each cycle.
It is not deployed.

Model: each SP appends a row listing the tables it wrote. The consumer runs
every X minutes, atomically claims pending rows, coalesces to a distinct table
set, full-snapshots each into PostgreSQL, then marks only the claimed rows done.