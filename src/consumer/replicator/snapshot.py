"""
snapshot.py  -  Full-snapshot replace of one table: SQL Server -> PostgreSQL.

Names come from mapping.py (the authoritative table_mapping.json):
  - SQL Server SELECT uses the mssql column names (e.g. [AccountNo])
  - PostgreSQL INSERT uses the snake_case pg names (e.g. account_no)
  - target table is the pg_table (e.g. dim_accounts)
So the consumer conforms exactly to the deployed schema.sql, never guessing.

Per table:
  1. Read ALL rows from SQL Server (explicit mssql column list).
  2. Load into a staging table in Postgres.
  3. Atomic swap in ONE transaction:
        TRUNCATE <pg_table>;  INSERT INTO <pg_table> SELECT * FROM <staging>;
     Readers see all-old or all-new, never a torn table.

Correctness:
  - Binary: VARBINARY -> bytes (pyodbc) -> bytea (psycopg). No decode anywhere.
  - Identity (Option A): SQL Server ID inserted explicitly; Postgres mints nothing,
    so every reload reproduces source IDs exactly.
  - FK-free mirror: plain TRUNCATE is safe (no reference ordering).
"""
from __future__ import annotations
import logging

from . import mapping

log = logging.getLogger("consumer.snapshot")


def _staging_name(pg_table: str) -> str:
    return f"{pg_table}_staging"


def snapshot_table(mssql_table: str, mssql, pgconn, fetch_batch: int) -> int:
    """
    Replace the Postgres mirror of `mssql_table` with current SQL Server contents.
    Returns rows loaded. Raises on failure (caller handles release/retry).
    All Postgres work commits in ONE transaction at the end (atomic swap).
    """
    pg_tbl = mapping.pg_table(mssql_table)
    staging = _staging_name(pg_tbl)
    mssql_cols = mapping.mssql_columns(mssql_table)
    pg_cols = mapping.pg_columns(mssql_table)

    src_col_sql = ", ".join(f"[{c}]" for c in mssql_cols)     # SQL Server side
    pg_col_sql = ", ".join(pg_cols)                            # Postgres side
    placeholders = ", ".join(["%s"] * len(pg_cols))

    # ---- 1. Read all rows from SQL Server ----
    src = mssql.cursor()
    src.execute(f"SELECT {src_col_sql} FROM {mssql_table};")

    total = 0
    with pgconn.cursor() as pg:
        # ---- 2. Fresh staging table shaped like the mirror ----
        pg.execute(f"DROP TABLE IF EXISTS {staging};")
        pg.execute(f"CREATE TABLE {staging} (LIKE {pg_tbl} INCLUDING DEFAULTS);")

        insert_sql = f"INSERT INTO {staging} ({pg_col_sql}) VALUES ({placeholders})"
        while True:
            rows = src.fetchmany(fetch_batch)
            if not rows:
                break
            # pyodbc Row -> tuple; bytes stay bytes (bytea), None stays NULL
            pg.executemany(insert_sql, [tuple(r) for r in rows])
            total += len(rows)

        # ---- 3. Atomic swap ----
        pg.execute(f"TRUNCATE {pg_tbl};")
        pg.execute(f"INSERT INTO {pg_tbl} ({pg_col_sql}) SELECT {pg_col_sql} FROM {staging};")
        pg.execute(f"DROP TABLE IF EXISTS {staging};")

    pgconn.commit()   # single commit -> swap is atomic to Postgres readers
    log.info("snapshot %s -> %s: %d rows", mssql_table, pg_tbl, total)
    return total


def snapshot_all(mssql_tables, mssql, pgconn, fetch_batch):
    """Snapshot each distinct table once. Any failure propagates to the caller."""
    results = {}
    for t in mssql_tables:
        if not mapping.is_replicated(t):
            log.warning("signal named non-replicated table %s - skipping", t)
            continue
        results[t] = snapshot_table(t, mssql, pgconn, fetch_batch)
    return results
