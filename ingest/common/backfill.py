"""
Backfill mode, shared by every ingest job that has one (decisions 0013, 0014).

A backfill is a one-off execution of a scheduled job with BACKFILL_START and
BACKFILL_END (YYYYMMDD, inclusive) set (`gcloud run jobs execute
--update-env-vars`, docs/runbook.md). The job pulls that day range instead of
its usual window, in batches of BATCH_DAYS that it fetches and loads one at a
time, so memory stays flat however long the range, and pauses PAUSE_SECONDS
between calls to go easy on the source.

Every batch shares the run's ingested_at (common/run.py), so afterwards the
affected silver models are rebuilt with --full-refresh (docs/runbook.md,
"Backfill a feed").
"""

# Import standard libraries
import datetime
import logging
import os
import time

# Import shared ingest helpers
from common.run import fail

# The inclusive day range to pull (unset outside a backfill), how many days
# each batch loads, and the pause between calls
BACKFILL_START = os.getenv('BACKFILL_START')
BACKFILL_END   = os.getenv('BACKFILL_END')
BATCH_DAYS     = 31
PAUSE_SECONDS  = 1.0  # ISO-NE blocks a caller making ~4 day-file calls a second (HTTP 429); decision 0013


def is_backfill():
    """Whether this run is a backfill (BACKFILL_START / BACKFILL_END set)."""
    return bool(BACKFILL_START or BACKFILL_END)


def backfill_days():
    """Every day from BACKFILL_START to BACKFILL_END inclusive, as dates; fails the job on a bad range."""
    try:
        start, end = (datetime.datetime.strptime(day, '%Y%m%d').date() for day in (BACKFILL_START, BACKFILL_END))
    except (TypeError, ValueError):
        fail(f"BACKFILL_START and BACKFILL_END must both be YYYYMMDD days (got {BACKFILL_START!r}, {BACKFILL_END!r})")
    if start > end:
        fail(f"BACKFILL_START ({BACKFILL_START}) is after BACKFILL_END ({BACKFILL_END})")
    return [start + datetime.timedelta(days=n) for n in range((end - start).days + 1)]


def backfill_batches():
    """The backfill range as consecutive batches of up to BATCH_DAYS dates, oldest first."""
    days = backfill_days()
    logging.info(f"Backfill: {len(days)} days, {days[0]} to {days[-1]}")
    return [days[i:i + BATCH_DAYS] for i in range(0, len(days), BATCH_DAYS)]


def pause(seconds=None):
    """Wait between calls during a backfill (PAUSE_SECONDS, or a source's own `seconds`); no-op otherwise."""
    if is_backfill():
        time.sleep(PAUSE_SECONDS if seconds is None else seconds)
