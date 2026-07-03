"""
db.py  -  Connection helpers for SQL Server (source) and PostgreSQL (target).

SQL Server via pyodbc (ODBC Driver 18). PostgreSQL via psycopg (v3).
Both drivers hand binary columns back/forth as native Python ``bytes``:
  - pyodbc returns VARBINARY as bytes
  - psycopg adapts bytes -> BYTEA and back
So the binary path is "bytes in, bytes out" with NO text decode anywhere,
which is exactly what the encrypted/hashed VARBINARY columns require.
"""

from __future__ import annotations
import contextlib
import pyodbc
import psycopg

from .config import Config


@contextlib.contextmanager
def mssql_conn(cfg: Config):
    conn = pyodbc.connect(cfg.mssql_odbc_connstr(), autocommit=False)
    try:
        yield conn
    finally:
        conn.close()


@contextlib.contextmanager
def pg_conn(cfg: Config):
    conn = psycopg.connect(
        host=cfg.pg_host,
        port=cfg.pg_port,
        dbname=cfg.pg_db,
        user=cfg.pg_user,
        password=cfg.pg_password,
        autocommit=False,
    )
    try:
        yield conn
    finally:
        conn.close()
