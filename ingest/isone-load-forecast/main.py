"""
Ingest: ISO-NE's hourly system load forecast, every version issued

Source:     ISO-NE web services, /hourlyloadforecast/all/day/{day} (ISO
            Express login; decision 0017). For each hour of the day, every
            forecast ISO-NE issued for it (about 10, from two days before
            through the day itself), each stamped with its CreationDate:
              LoadMw     forecast system load
              NetLoadMw  forecast load net of ISO-NE's adjustments (equal to
                         LoadMw in the hours checked)
Cadence:    Every 6 hours
Each run:   Yesterday (every version, now complete) and tomorrow (the versions
            issued so far). Bronze keeps each run's copy; silver keeps each
            hour × version once. A backfill (common/backfill.py) pulls a day
            range, a month at a time.
Writes to:  bronze.isone_load_forecast (append) — one row per hour × version × run

ISO-NE's forecast is the benchmark a load model has to beat: silver's
__day_ahead view is the version a day-ahead model competes with.
"""

# Import standard libraries
import logging

# Import shared ingest helpers
from common.isone import day_batches, eastern_days, fetch_days, to_frame
from common.load import append_to_bronze

# Record fields, kept under ISO-NE's names (bronze keeps the source's names)
MEASURES = ['LoadMw', 'NetLoadMw']
COLUMNS  = ['BeginDate', 'CreationDate', *MEASURES]

# One batch of days at a time (yesterday and tomorrow, unless backfilling)
for days in day_batches(eastern_days([-1, 1])):

    # ── Fetch ─────────────────────────────────────────────────────────────────

    records = fetch_days('hourlyloadforecast/all', days)

    # ── Shape ─────────────────────────────────────────────────────────────────

    df = (
        to_frame(records, COLUMNS, time_columns=['BeginDate', 'CreationDate'])
        .astype(dict.fromkeys(MEASURES, 'float64'))
    )
    if not df.empty:
        logging.info(f"Shaped {len(df)} rows: {df['BeginDate'].min()} to {df['BeginDate'].max()}")

    # ── Write ─────────────────────────────────────────────────────────────────

    append_to_bronze(df)
