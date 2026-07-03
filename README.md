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