"""
run_once.py  -  Execute exactly ONE replication cycle, then exit.

This is the on-demand entry point. The laptop triggers it over SSH:

    ssh <pi> "docker exec replicator-test python -m replicator.run_once"

Unlike main.py (which loops on a timer), this runs a single
reap -> claim -> snapshot -> complete cycle and returns. The process exit
code tells the SSH caller what happened, so the laptop's port-gate script
knows when the backup is done (and whether it succeeded) before closing the
firewall port:

    exit 0  -> cycle ran and completed cleanly (or there was nothing to do)
    exit 1  -> the cycle failed (claimed rows were released for retry)
    exit 2  -> configuration/startup error (bad or missing env)

Because run_cycle() already handles its own failures internally (it releases
claimed rows and does not re-raise), a "failure" here is detected by checking
whether the cycle raised at the top level - which only happens on unexpected
errors like the SQL Server connection failing to open at all.
"""

from __future__ import annotations
import logging
import sys
import time

from .config import Config
from .main import run_cycle

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)sZ %(levelname)s %(name)s: %(message)s",
)
logging.Formatter.converter = time.gmtime  # UTC logs, matching the outbox timestamps
log = logging.getLogger("replicator.run_once")


def main() -> int:
    try:
        cfg = Config()
    except SystemExit:
        # Config() calls sys.exit(2) on bad/missing env; surface that code.
        raise
    except Exception:
        log.exception("configuration error")
        return 2

    log.info("run_once starting: %s", cfg.summary())
    try:
        run_cycle(cfg)
    except Exception:
        # run_cycle handles snapshot failures internally; reaching here means
        # something unexpected (e.g. SQL Server unreachable when opening the
        # connection). Report failure so the caller does not assume success.
        log.exception("run_once failed")
        return 1

    log.info("run_once complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
