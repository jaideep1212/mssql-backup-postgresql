"""
mapping.py  -  Loads the authoritative SQL Server <-> PostgreSQL field map.

table_mapping.json is generated from schema.sql (the deployed Postgres DDL) and
is the single source of truth for names. The consumer uses it to translate each
SQL Server column to its snake_case PostgreSQL name at snapshot time, rather than
guessing by lowercasing - so the consumer can never drift from the deployed schema.
"""

from __future__ import annotations
import json
import os
from functools import lru_cache

_MAPPING_PATH = os.path.join(os.path.dirname(__file__), "table_mapping.json")


@lru_cache(maxsize=1)
def _load() -> dict:
    with open(_MAPPING_PATH, "r", encoding="utf-8") as fh:
        return json.load(fh)


def replicated_tables() -> list[str]:
    """SQL Server table names (e.g. 'dbo.DimUsers') that are replicated."""
    return list(_load()["tables"].keys())


def pg_table(mssql_table: str) -> str:
    """PostgreSQL table name for a SQL Server table (e.g. 'dbo.DimUsers' -> 'dim_users')."""
    return _load()["tables"][mssql_table]["pg_table"]


def column_pairs(mssql_table: str) -> list[tuple[str, str]]:
    """Ordered [(mssql_col, pg_col), ...] for a table."""
    return [(c["mssql"], c["pg"]) for c in _load()["tables"][mssql_table]["columns"]]


def mssql_columns(mssql_table: str) -> list[str]:
    return [m for m, _ in column_pairs(mssql_table)]


def pg_columns(mssql_table: str) -> list[str]:
    return [p for _, p in column_pairs(mssql_table)]


def is_replicated(mssql_table: str) -> bool:
    return mssql_table in _load()["tables"]
