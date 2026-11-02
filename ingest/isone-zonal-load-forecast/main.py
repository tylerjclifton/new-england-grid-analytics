"""
Ingest: ISO-NE's hourly load forecast per load zone, every version issued

Source:     ISO-NE web services, /reliabilityregionloadforecast/day/{day}/all
            (ISO Express login; decision 0017). For each hour of the day and
            each of the eight load zones (ISO-NE calls them reliability
            regions here, named like .Z.CONNECTICUT), every forecast issued
            for it (about 9), each stamped with its CreationDate:
              LoadMw                            forecast load in the zone
              ReliabilityRegionLoadPercentage   the zone's share of the
                                                system forecast, %
Cadence:    Every 6 hours
Each run:   Yesterday (every version, now complete) and tomorrow (the versions
            issued so far). Bronze keeps each run's copy; silver keeps each
            hour × zone × version once. A backfill (common/backfill.py) pulls
            a day range, a month at a time.
Writes to:  bronze.isone_zonal_load_forecast (append) — one row per hour ×
            zone × version × run
"""

# Import standard libraries
import logging

# Import shared ingest helpers
from common.isone import day_batches, eastern_days, fetch_days, to_frame
from common.load import append_to_bronze

# Record fields, kept under ISO-NE's names (bronze keeps the source's names)
MEASURES = ['LoadMw', 'ReliabilityRegionLoadPercentage']
COLUMNS  = ['BeginDate', 'CreationDate', 'ReliabilityRegion', *MEASURES]

# One batch of days at a time (yesterday and tomorrow, unless backfilling)
for days in day_batches(eastern_days([-1, 1])):

    # ── Fetch ─────────────────────────────────────────────────────────────────

    records = fetch_days('reliabilityregionloadforecast', days, suffix='/all')

    # ── Shape ─────────────────────────────────────────────────────────────────

    df = (
        to_frame(records, COLUMNS, time_columns=['BeginDate', 'CreationDate'])
        .astype(dict.fromkeys(MEASURES, 'float64'))
    )
    if not df.empty:
        logging.info(f"Shaped {len(df)} rows: {df['BeginDate'].min()} to {df['BeginDate'].max()}")

    # ── Write ─────────────────────────────────────────────────────────────────

    append_to_bronze(df)
