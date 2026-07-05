"""
conftest.py  -  shared pytest fixtures.

The DB drivers (pyodbc, psycopg) are heavy and not needed for unit tests, so
we stub them in sys.modules before any replicator module imports them. This
lets the whole suite run on a plain machine (and in CI) with no databases and
no ODBC driver installed.
"""
import sys
import types
import pytest


# ---- Stub the DB drivers so importing replicator.* never needs them ----
def _install_driver_stubs():
    if "pyodbc" not in sys.modules:
        pyodbc = types.ModuleType("pyodbc")
        # minimal exception classes the code references
        pyodbc.Error = type("Error", (Exception,), {})
        pyodbc.OperationalError = type("OperationalError", (pyodbc.Error,), {})
        pyodbc.ProgrammingError = type("ProgrammingError", (pyodbc.Error,), {})
        pyodbc.InterfaceError = type("InterfaceError", (pyodbc.Error,), {})
        pyodbc.connect = lambda *a, **k: None
        sys.modules["pyodbc"] = pyodbc
    if "psycopg" not in sys.modules:
        psycopg = types.ModuleType("psycopg")
        psycopg.connect = lambda *a, **k: None
        sys.modules["psycopg"] = psycopg


_install_driver_stubs()


class FakeCursor:
    """
    A stand-in for a pyodbc cursor that records executed SQL and returns
    canned rows. Deliberately simple - it models the surface the code uses:
    execute(sql, *params), fetchall(), and rowcount.
    """
    def __init__(self, rows=None, rowcount=0):
        self._rows = rows or []
        self.rowcount = rowcount
        self.executed = []          # list of (sql, params) tuples

    def execute(self, sql, *params):
        self.executed.append((sql, params))
        return self

    def fetchall(self):
        return self._rows

    @property
    def last_sql(self):
        return self.executed[-1][0] if self.executed else ""

    @property
    def all_sql(self):
        return "\n".join(sql for sql, _ in self.executed)


@pytest.fixture
def cursor():
    """A fresh FakeCursor with no rows."""
    return FakeCursor()


@pytest.fixture
def clean_env(monkeypatch):
    """Remove all replicator-relevant env vars so each test sets its own."""
    for k in list(__import__("os").environ):
        if k.startswith(("LANE", "MSSQL_", "PG_", "INTERVAL_", "REAPER_", "FETCH_")):
            monkeypatch.delenv(k, raising=False)
    return monkeypatch


def set_valid_test_env(monkeypatch):
    """Populate a complete, valid TEST-lane environment."""
    env = {
        "LANE": "TEST",
        "MSSQL_HOST": "192.168.1.199",
        "MSSQL_PORT": "1433",
        "MSSQL_AUTH": "sql",
        "MSSQL_USER_TEST": "svcreader",
        "MSSQL_DB_TEST": "LocalTestDB",
        "MSSQL_PASSWORD_TEST": "secret",
        "MSSQL_ENCRYPT": "no",
        "MSSQL_TRUST_SERVER_CERT": "yes",
        "PG_HOST": "postgres",
        "PG_PORT": "5432",
        "PG_USER_TEST": "svcbackup",
        "PG_DB_TEST": "household_test",
        "PG_PASSWORD_TEST": "secret2",
        "FETCH_BATCH": "5000",
    }
    for k, v in env.items():
        monkeypatch.setenv(k, v)
