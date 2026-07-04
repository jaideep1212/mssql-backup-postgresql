"""
test_outbox.py  -  outbox lifecycle logic.

distinct_tables() is pure and fully unit-testable. The claim/complete/release
functions are tested against a FakeCursor to lock in their SQL shape and, for
claim_pending, to guard the specific pyodbc regression (SET NOCOUNT ON must be
present so fetchall lands on the SELECT, not the UPDATE row count).
"""
import pytest
from conftest import FakeCursor
from replicator import outbox


# ---------- distinct_tables (pure logic) ----------

def test_distinct_tables_dedupes_across_rows():
    claimed = [
        (1, '["dbo.DimUsers","dbo.DimUsers_S"]'),
        (2, '["dbo.DimUsers"]'),
        (3, '["dbo.FactAliases"]'),
    ]
    result = outbox.distinct_tables(claimed)
    assert result == ["dbo.DimUsers", "dbo.DimUsers_S", "dbo.FactAliases"]


def test_distinct_tables_empty_input():
    assert outbox.distinct_tables([]) == []


def test_distinct_tables_single_table_many_rows():
    claimed = [(i, '["dbo.DimUsers"]') for i in range(10)]
    assert outbox.distinct_tables(claimed) == ["dbo.DimUsers"]


def test_distinct_tables_skips_malformed_json():
    # a broken payload should be skipped, not crash the whole cycle
    claimed = [
        (1, '["dbo.DimUsers"]'),
        (2, 'not-valid-json'),
        (3, '["dbo.FactAliases"]'),
    ]
    result = outbox.distinct_tables(claimed)
    assert result == ["dbo.DimUsers", "dbo.FactAliases"]


def test_distinct_tables_result_is_sorted():
    claimed = [(1, '["dbo.Zebra","dbo.Apple"]')]
    assert outbox.distinct_tables(claimed) == ["dbo.Apple", "dbo.Zebra"]


# ---------- claim_pending (SQL shape + pyodbc regression guard) ----------

def test_claim_pending_includes_set_nocount_on():
    # REGRESSION GUARD: without SET NOCOUNT ON, pyodbc raises
    # "No results. Previous SQL was not a query" because fetchall lands on
    # the UPDATE's row count instead of the SELECT. This test locks that fix.
    cur = FakeCursor(rows=[])
    outbox.claim_pending(cur)
    assert "SET NOCOUNT ON" in cur.last_sql


def test_claim_pending_claims_only_pending_rows():
    cur = FakeCursor(rows=[])
    outbox.claim_pending(cur)
    sql = cur.last_sql
    assert "WHERE BackupDone = 0" in sql        # only pending
    assert "BackupDone = 2" in sql              # flips to claimed
    assert "OUTPUT inserted.EventId" in sql     # captures ids atomically


def test_claim_pending_parses_rows():
    cur = FakeCursor(rows=[(1, '["dbo.DimUsers"]'), (2, '["dbo.FactAliases"]')])
    result = outbox.claim_pending(cur)
    assert result == [(1, '["dbo.DimUsers"]'), (2, '["dbo.FactAliases"]')]
    # ids coerced to int
    assert isinstance(result[0][0], int)


# ---------- complete ----------

def test_complete_no_ids_is_noop():
    cur = FakeCursor()
    outbox.complete(cur, [])
    assert cur.executed == []                   # nothing issued


def test_complete_marks_done():
    cur = FakeCursor()
    outbox.complete(cur, [1, 2, 3])
    sql = cur.last_sql
    assert "BackupDone = 1" in sql
    # one placeholder per id
    assert sql.count("?") == 3


# ---------- release ----------

def test_release_no_ids_is_noop():
    cur = FakeCursor()
    outbox.release(cur, [], "err")
    assert cur.executed == []


def test_release_returns_to_pending():
    cur = FakeCursor()
    outbox.release(cur, [5], "boom")
    sql = cur.last_sql
    assert "BackupDone = 0" in sql              # back to pending
    assert "LastError" in sql


# ---------- reap_stale ----------

def test_reap_stale_targets_claimed_rows():
    cur = FakeCursor(rowcount=2)
    n = outbox.reap_stale(cur, 15)
    sql = cur.last_sql
    assert "BackupDone = 2" in sql              # only stuck-claimed
    assert "BackupDone = 0" in sql              # reset to pending
    assert n == 2
