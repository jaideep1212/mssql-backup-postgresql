"""
main.py  -  The consumer's timer loop.

Every INTERVAL_MINUTES:
    reaper -> claim -> distinct tables -> snapshot each -> complete (or release).

One cycle owns its claimed rows end to end. On success the claimed rows are
marked done; on any failure they are released back to pending so the next cycle
retries (full-snapshot is idempotent, so retry is always safe).

The loop is self-contained (no external scheduler). To switch to an external
cron/systemd timer later, call run_cycle() once per invocation instead of loop().
"""

from __future__ import annotations
import logging
import sys
import time

from .config import Config
from .db import mssql_conn, pg_conn
from . import outbox
from .snapshot import snapshot_all

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)sZ %(levelname)s %(name)s: %(message)s",
)
# All timestamps in logs are UTC.
logging.Formatter.converter = time.gmtime
log = logging.getLogger("consumer.main")


def run_cycle(cfg: Config) -> None:
    """Execute a single reaper->claim->snapshot->complete cycle."""
    with mssql_conn(cfg) as mssql:
        cur = mssql.cursor()

        # Reaper first, so crash-stranded rows rejoin this cycle.
        reaped = outbox.reap_stale(cur, cfg.reaper_stale_minutes)
        if reaped:
            log.warning("reaper released %d stale claimed row(s)", reaped)

        claimed = outbox.claim_pending(cur)
        mssql.commit()  # commit the claim (and reaper) before doing slow work

        if not claimed:
            log.info("nothing pending")
            return

        event_ids = [eid for eid, _ in claimed]
        tables = outbox.distinct_tables(claimed)
        log.info(
            "claimed %d row(s) -> %d distinct table(s): %s",
            len(claimed),
            len(tables),
            ", ".join(tables),
        )

        try:
            with pg_conn(cfg) as pg:
                snapshot_all(tables, mssql, pg, cfg.fetch_batch)
            # All snapshots committed -> mark the claimed rows done.
            outbox.complete(cur, event_ids)
            mssql.commit()
            log.info("cycle complete: %d row(s) done", len(event_ids))
        except Exception as exc:  # noqa: BLE001 - we want to catch-and-release
            log.exception("snapshot failed; releasing claimed rows for retry")
            try:
                outbox.release(cur, event_ids, repr(exc))
                mssql.commit()
            except Exception:  # noqa: BLE001
                log.exception(
                    "failed to release claimed rows; reaper will recover them"
                )
            # Do not re-raise: the loop should survive and retry next cycle.


def loop(cfg: Config) -> None:
    log.info("consumer starting: %s", cfg.summary())
    while True:
        started = time.monotonic()
        try:
            run_cycle(cfg)
        except Exception:  # noqa: BLE001 - never let the loop die
            log.exception("unexpected error in cycle; continuing")
        elapsed = time.monotonic() - started
        sleep_for = max(0, cfg.interval_seconds - elapsed)
        log.info("sleeping %.0fs", sleep_for)
        time.sleep(sleep_for)


def main() -> int:
    cfg = Config()
    loop(cfg)
    return 0


if __name__ == "__main__":
    sys.exit(main())
