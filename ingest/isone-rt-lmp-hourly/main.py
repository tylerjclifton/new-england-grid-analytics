"""
Ingest: ISO-NE hourly real-time prices (LMPs), final — backfill only

Source:     ISO-NE web services, /hourlylmp/rt/final/day/{day} (ISO Express
            login; decisions 0012, 0013): one call per day for every location
            (~1,200, 6 MB), keeping the Hub and the eight load zones
            (common/isone.py), which keeps the backfill within ISO-NE's
            request limit. Each hourly price is the mean of that hour's twelve
            five-minute prices.
Cadence:    None. Run as a one-off backfill (BACKFILL_START / BACKFILL_END),
            for the years before ISO-NE's five-minute history begins (2024);
            from there on isone-rt-lmp's five-minute prices cover real time,
            and hourly is derived from them.
Each run:   Final prices for every day in the backfill range, a month at a time.
Writes to:  bronze.isone_rt_lmp_hourly (append) — one row per hour × location × run
"""

# Import shared ingest helpers
from common.backfill import is_backfill
from common.isone import (
    LMP_COLUMNS,
    LMP_PRICES,
    at_pricing_location,
    day_batches,
    fetch_days,
    flatten_location,
    to_frame,
)
from common.load import append_to_bronze
from common.run import fail

# Backfill only: a scheduled run would duplicate the five-minute feed
if not is_backfill():
    fail("isone-rt-lmp-hourly runs only as a backfill: set BACKFILL_START and BACKFILL_END (docs/runbook.md)")

# One batch of days at a time
for days in day_batches():

    # ── Fetch ─────────────────────────────────────────────────────────────────

    records = fetch_days('hourlylmp/rt/final', days, keep=at_pricing_location)

    # ── Shape ─────────────────────────────────────────────────────────────────

    df = (
        to_frame([flatten_location(record) for record in records], LMP_COLUMNS)
        .astype(dict.fromkeys(LMP_PRICES, 'float64'))
    )

    # ── Write ─────────────────────────────────────────────────────────────────

    append_to_bronze(df, time_column='BeginDate')
