"""
outbox.py  -  The dbo.BackupOutbox lifecycle, in code.

Implements exactly the cycle from 02_consumer_cycle.reference.sql:
    reaper -> claim (0->2, capture IDs) -> distinct tables -> [snapshot] ->
    complete claimed IDs (2->1)  OR  release on failure (2->0).

The atomic claim is the crux: a single UPDATE ... OUTPUT both flips pending
rows to 'claimed' and returns their EventIds, under one lock. Rows inserted
after the claim stay at 0 and are picked up next cycle - so a mid-cycle SP
insert is never marked done without being backed up.

All statements run against SQL Server. State codes: 0=pending, 2=claimed, 1=done.
"""

from __future__ import annotations
import json
import logging

log = logging.getLogger("replicator.outbox")


def reap_stale(cursor, stale_minutes: int) -> int:
    """Release rows stuck 'claimed' from a crashed prior cycle (2 -> 0)."""
    cursor.execute(
        """
        UPDATE dbo.BackupOutbox
        SET BackupDone = 0, ModifiedUtc = SYSUTCDATETIME()
        WHERE BackupDone = 2
          AND ModifiedUtc < DATEADD(MINUTE, -?, SYSUTCDATETIME());
        """,
        stale_minutes,
    )
    return cursor.rowcount


def claim_pending(cursor) -> list[tuple[int, str]]:
    """
    Atomically claim all pending rows and return [(EventId, TableNames_json), ...].
    The UPDATE ... OUTPUT is a single locked operation: capture == claim.
    """
    # SET NOCOUNT ON suppresses the UPDATE's "rows affected" count so pyodbc
    # lands directly on the final SELECT's result set. Without it, fetchall()
    # sees the UPDATE's non-query response and raises "No results / not a query".
    cursor.execute(
        """
        SET NOCOUNT ON;
        DECLARE @claimed TABLE (EventId BIGINT PRIMARY KEY, TableNames NVARCHAR(MAX));
        UPDATE dbo.BackupOutbox
        SET BackupDone = 2, ModifiedUtc = SYSUTCDATETIME(), Attempts = Attempts + 1
        OUTPUT inserted.EventId, inserted.TableNames INTO @claimed
        WHERE BackupDone = 0;
        SELECT EventId, TableNames FROM @claimed ORDER BY EventId;
        """
    )
    return [(int(r[0]), r[1]) for r in cursor.fetchall()]


def distinct_tables(claimed: list[tuple[int, str]]) -> list[str]:
    """Union the per-row JSON table arrays into a de-duplicated, sorted list."""
    seen: set[str] = set()
    for _eid, table_json in claimed:
        try:
            for t in json.loads(table_json):
                seen.add(t)
        except (json.JSONDecodeError, TypeError):
            log.warning("skipping malformed TableNames payload: %r", table_json)
    return sorted(seen)


def complete(cursor, event_ids: list[int]) -> None:
    """Mark ONLY the claimed rows done (2 -> 1)."""
    if not event_ids:
        return
    placeholders = ",".join("?" for _ in event_ids)
    cursor.execute(
        f"""
        UPDATE dbo.BackupOutbox
        SET BackupDone = 1, ModifiedUtc = SYSUTCDATETIME()
        WHERE EventId IN ({placeholders});
        """,
        *event_ids,
    )


def release(cursor, event_ids: list[int], error: str) -> None:
    """On handled failure, return claimed rows to pending (2 -> 0) to retry next cycle."""
    if not event_ids:
        return
    placeholders = ",".join("?" for _ in event_ids)
    cursor.execute(
        f"""
        UPDATE dbo.BackupOutbox
        SET BackupDone = 0, ModifiedUtc = SYSUTCDATETIME(), LastError = ?
        WHERE EventId IN ({placeholders});
        """,
        error[:4000],
        *event_ids,
    )
