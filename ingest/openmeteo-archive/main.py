"""
Ingest: Open-Meteo hourly reanalysis (the best estimate of past weather), one
point per ISO-NE load zone

Source:     Open-Meteo archive API (archive-api.open-meteo.com, no key; decision
            0015): ERA5-based reanalysis, consistent back decades and current
            to about yesterday. Same points and variables as the forecast
            (common/openmeteo.py).
Cadence:    Daily
Each run:   The last 14 days through yesterday (UTC), since the newest days
            are refined after the fact; bronze keeps every version. A backfill
            (common/backfill.py) pulls a day range a month at a time, from
            2015-07 to match EIA's demand history.
Writes to:  bronze.openmeteo_archive (append) — one row per load zone × hour × run

This is weather to explain what happened with. A model predicting ahead must
train on forecasts as they were issued (openmeteo_previous_runs, and the
forecast job's snapshots) instead, or it learns from information it won't have.
"""

# Import standard libraries
import datetime
import os

# Import shared ingest helpers
from common.backfill import backfill_batches, is_backfill, pause
from common.load import append_to_bronze
from common.openmeteo import BACKFILL_PAUSE_SECONDS, HOURLY_VARIABLES, fetch_points, to_frame

ARCHIVE_URL   = 'https://archive-api.open-meteo.com/v1/archive'
LOOKBACK_DAYS = int(os.getenv('LOOKBACK_DAYS', '14'))

# Date ranges to pull (inclusive, UTC days): the last two weeks, or the
# backfill range a month at a time
if is_backfill():
    ranges = [(batch[0], batch[-1]) for batch in backfill_batches()]
else:
    today = datetime.datetime.now(datetime.timezone.utc).date()
    ranges = [(today - datetime.timedelta(days=LOOKBACK_DAYS), today - datetime.timedelta(days=1))]

for start, end in ranges:

    # ── Fetch ─────────────────────────────────────────────────────────────────

    points = fetch_points(ARCHIVE_URL, {
        'hourly':     ','.join(HOURLY_VARIABLES),
        'start_date': start.isoformat(),
        'end_date':   end.isoformat(),
    })

    # ── Shape and write ───────────────────────────────────────────────────────

    append_to_bronze(to_frame(points, HOURLY_VARIABLES))
    pause(BACKFILL_PAUSE_SECONDS)
