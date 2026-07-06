"""
test_config.py  -  Config env parsing, lane pinning, and connection-string building.
"""

import pytest
from conftest import set_valid_test_env

from replicator.config import Config


# ---------- lane pinning ----------


def test_valid_test_lane_loads(clean_env):
    set_valid_test_env(clean_env)
    cfg = Config()
    assert cfg.lane == "TEST"
    assert cfg.mssql_db == "LocalTestDB"
    assert cfg.pg_db == "household_test"


def test_lane_is_uppercased(clean_env):
    set_valid_test_env(clean_env)
    clean_env.setenv("LANE", "test")  # lowercase
    cfg = Config()
    assert cfg.lane == "TEST"


def test_invalid_lane_exits(clean_env):
    set_valid_test_env(clean_env)
    clean_env.setenv("LANE", "STAGING")
    with pytest.raises(SystemExit):
        Config()


def test_missing_lane_exits(clean_env):
    # nothing set at all
    with pytest.raises(SystemExit):
        Config()


# ---------- per-lane variable resolution ----------


def test_prod_lane_reads_prod_suffixed_vars(clean_env):
    set_valid_test_env(clean_env)
    clean_env.setenv("LANE", "PROD")
    clean_env.setenv("MSSQL_USER_PROD", "svcreader")
    clean_env.setenv("MSSQL_DB_PROD", "LocalProdDB")
    clean_env.setenv("MSSQL_PASSWORD_PROD", "p")
    clean_env.setenv("PG_USER_PROD", "svcbackup")
    clean_env.setenv("PG_DB_PROD", "household_prod")
    clean_env.setenv("PG_PASSWORD_PROD", "p2")
    cfg = Config()
    assert cfg.mssql_db == "LocalProdDB"
    assert cfg.pg_db == "household_prod"


def test_test_lane_does_not_read_prod_password(clean_env):
    # Structural isolation: TEST lane must not require or read PROD vars.
    set_valid_test_env(clean_env)
    # No *_PROD vars set at all - should still load fine on TEST.
    cfg = Config()
    assert cfg.mssql_password == "secret"


# ---------- required vars ----------


def test_missing_required_var_exits(clean_env):
    set_valid_test_env(clean_env)
    clean_env.delenv("MSSQL_HOST", raising=False)
    with pytest.raises(SystemExit):
        Config()


# ---------- integer parsing ----------


def test_interval_minutes_to_seconds(clean_env):
    set_valid_test_env(clean_env)
    clean_env.setenv("INTERVAL_MINUTES", "3")
    cfg = Config()
    assert cfg.interval_seconds == 180


def test_interval_defaults_when_absent(clean_env):
    set_valid_test_env(clean_env)
    clean_env.delenv("INTERVAL_MINUTES", raising=False)
    cfg = Config()
    assert cfg.interval_seconds == 300  # default 5 min


def test_non_integer_int_var_exits(clean_env):
    set_valid_test_env(clean_env)
    clean_env.setenv("MSSQL_PORT", "notaport")
    with pytest.raises(SystemExit):
        Config()


# ---------- connection string (SQL auth) ----------


def test_connstr_sql_auth_has_uid_pwd(clean_env):
    set_valid_test_env(clean_env)
    cfg = Config()
    s = cfg.mssql_odbc_connstr()
    assert "UID=svcreader" in s
    assert "PWD=secret" in s
    assert "SERVER=192.168.1.199,1433" in s
    assert "DATABASE=LocalTestDB" in s
    assert "Encrypt=no" in s
    assert "TrustServerCertificate=yes" in s
    assert "Trusted_Connection" not in s  # not windows auth


# ---------- connection string (windows auth) ----------


def test_connstr_windows_auth_uses_trusted_connection(clean_env):
    set_valid_test_env(clean_env)
    clean_env.setenv("MSSQL_AUTH", "windows")
    # windows auth should NOT require user/password
    clean_env.delenv("MSSQL_USER_TEST", raising=False)
    clean_env.delenv("MSSQL_PASSWORD_TEST", raising=False)
    cfg = Config()
    s = cfg.mssql_odbc_connstr()
    assert "Trusted_Connection=yes" in s
    assert "UID=" not in s
    assert "PWD=" not in s


# ---------- summary must not leak secrets ----------


def test_summary_has_no_password(clean_env):
    set_valid_test_env(clean_env)
    cfg = Config()
    summary = cfg.summary()
    assert "secret" not in summary
    assert "svcreader" not in summary or "PWD" not in summary  # password never present
    assert "TEST" in summary
