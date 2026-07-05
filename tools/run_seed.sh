#!/usr/bin/env bash
#
# run_seed.sh  -  seed dbo.TestTbl by running seed_testtbl.py INSIDE the
# replicator container (which already has pyodbc + the ODBC driver). Bundles the
# steps that were previously manual: ensure cryptography is present, copy the
# script + .env into the container, and run it.
#
# Prereqs:
#   - the replicator-test container is up
#   - tools/.env has ENCRYPTION_KEY_TEST + MSSQL_*_TEST (values UNQUOTED)
#   - MSSQL_USER_TEST can INSERT into dbo.TestTbl (e.g. svcreader granted INSERT)
#   - the SQL Server firewall port is OPEN while this runs
#
# Usage:
#   ./run_seed.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER="replicator-test"
SEED="seed_testtbl.py"
ENV_FILE=".env"

echo ">> checking container is running"
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "ERROR: container '${CONTAINER}' is not running." >&2
    exit 1
fi

echo ">> ensuring cryptography is installed in the container"
# quiet no-op if already there
docker exec "$CONTAINER" python -c "import cryptography" 2>/dev/null \
    || docker exec "$CONTAINER" pip install -q cryptography

echo ">> copying seed script and .env into the container (/tmp)"
docker cp "$SCRIPT_DIR/$SEED"     "$CONTAINER:/tmp/$SEED"
docker cp "$SCRIPT_DIR/$ENV_FILE" "$CONTAINER:/tmp/$ENV_FILE"

echo ">> running the seed inside the container"
docker exec -w /tmp "$CONTAINER" python "/tmp/$SEED"

echo ""
echo ">> seed complete."
echo ">> NEXT: queue an outbox row for dbo.TestTbl, then trigger a cycle:"
echo "     (SSMS)  INSERT INTO dbo.BackupOutbox (TableNames, BackupDone, CreatedUtc)"
echo "             VALUES (N'[\"dbo.TestTbl\"]', 0, SYSUTCDATETIME());"
echo "     (Pi)    docker exec $CONTAINER python -m replicator.run_once"
