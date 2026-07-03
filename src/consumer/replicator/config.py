"""
config.py  -  Consumer configuration, entirely from environment variables.

Lane pinning is STRUCTURAL: LANE is read once at startup and the whole process
is bound to one environment. There is no per-cycle or per-message switch, so a
test consumer can never write prod, and vice versa - the separation is enforced
by which env vars the container was started with, not by runtime logic.

No secrets live in code. The container is started with the right environment
(see .env.example); the same image runs both lanes with different env.
"""
from __future__ import annotations
import os
import sys


def _req(name: str) -> str:
    val = os.environ.get(name)
    if not val:
        sys.stderr.write(f"[config] FATAL: required env var {name} is not set\n")
        sys.exit(2)
    return val


def _int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        sys.stderr.write(f"[config] FATAL: {name}={raw!r} is not an integer\n")
        sys.exit(2)


class Config:
    def __init__(self) -> None:
        # ---- Lane: PROD or TEST, pinned for the life of the process ----
        self.lane = _req("LANE").upper()
        if self.lane not in ("PROD", "TEST"):
            sys.stderr.write(f"[config] FATAL: LANE must be PROD or TEST, got {self.lane!r}\n")
            sys.exit(2)

        # ---- Timer ----
        self.interval_seconds = _int("INTERVAL_MINUTES", 5) * 60
        # Rows stuck 'claimed' longer than this are reclaimed by the reaper.
        self.reaper_stale_minutes = _int("REAPER_STALE_MINUTES", 15)

        # ---- SQL Server (source) ----
        self.mssql_host = _req("MSSQL_HOST")          # server name, e.g. MYSERVER\SQLEXPRESS or host.domain
        self.mssql_port = _int("MSSQL_PORT", 1433)
        self.mssql_db = _req(f"MSSQL_DB_{self.lane}")              # LocalTestDB (LocalProdDB later)

        # Auth mode: "sql" (dedicated SQL login, default) or "windows" (integrated/Kerberos).
        self.mssql_auth = os.environ.get("MSSQL_AUTH", "sql").lower()
        if self.mssql_auth == "sql":
            self.mssql_user = _req("MSSQL_USER")      # e.g. svc_replication_reader
            self.mssql_password = _req(f"MSSQL_PASSWORD_{self.lane}")
        else:
            # Windows/integrated auth: no username/password in config; the
            # container must supply a Kerberos identity (keytab + krb5.conf).
            self.mssql_user = None
            self.mssql_password = None

        # ODBC Driver 18 defaults to Encrypt=yes; allow opting out on a trusted LAN.
        self.mssql_encrypt = os.environ.get("MSSQL_ENCRYPT", "no")
        self.mssql_trust_cert = os.environ.get("MSSQL_TRUST_SERVER_CERT", "yes")

        # ---- PostgreSQL (target) ----
        self.pg_host = _req("PG_HOST")
        self.pg_port = _int("PG_PORT", 5432)
        self.pg_db = _req(f"PG_DB_{self.lane}")                # proddb or testdb
        self.pg_user = _req("PG_USER")
        self.pg_password = _req(f"PG_PASSWORD_{self.lane}")

        # ---- Snapshot read batching (rows fetched per round-trip) ----
        self.fetch_batch = _int("FETCH_BATCH", 5000)

    def mssql_odbc_connstr(self) -> str:
        base = (
            "DRIVER={ODBC Driver 18 for SQL Server};"
            f"SERVER={self.mssql_host},{self.mssql_port};"
            f"DATABASE={self.mssql_db};"
        )
        if self.mssql_auth == "sql":
            base += f"UID={self.mssql_user};PWD={self.mssql_password};"
        else:
            # Integrated/Kerberos auth — no UID/PWD; identity comes from the environment.
            base += "Trusted_Connection=yes;"
        base += (
            f"Encrypt={self.mssql_encrypt};"
            f"TrustServerCertificate={self.mssql_trust_cert};"
        )
        return base

    def summary(self) -> str:
        # Safe to log: no secrets.
        return (
            f"lane={self.lane} interval={self.interval_seconds}s "
            f"mssql={self.mssql_host}:{self.mssql_port}/{self.mssql_db} "
            f"pg={self.pg_host}:{self.pg_port}/{self.pg_db}"
        )
