"""
Ingest: ISO-NE hourly day-ahead prices (LMPs)

Source:     ISO-NE web services, /hourlylmp/da/final/day/{day} (ISO Express
            login; decisions 0012, 0013): one call per day for every location
            (~1,200, 6 MB), keeping the Hub and the eight load zones
            (common/isone.py). One call a day, not nine, keeps backfills
            within ISO-NE's request limit. The
            day-ahead market clears around midday for the next day, and its
            prices are final when published: the market's forecast of
            tomorrow's real-time prices.
Cadence:    Every 6 hours
Each run:   Today and tomorrow. Tomorrow is empty until the market clears, so
            the first run after it (18:10 Eastern) picks it up. A backfill
            pulls a day range instead, a month at a time (decision 0013).
Writes to:  bronze.isone_da_lmp (append) — one row per hour × location × run
"""

# Import standard libraries
import logging

# Import shared ingest helpers
from common.isone import at_pricing_location, day_batches, eastern_days, fetch_days, flatten_location, to_frame
from common.load import append_to_bronze

# Record fields under ISO-NE's names (the location flattened by flatten_location)
PRICES  = ['LmpTotal', 'EnergyComponent', 'CongestionComponent', 'LossComponent']
COLUMNS = ['BeginDate', 'LocId', 'LocType', 'LocName', *PRICES]

# One batch of days at a time (today and tomorrow, unless backfilling)
for days in day_batches(eastern_days([0, 1])):

    # ── Fetch ─────────────────────────────────────────────────────────────────

    records = fetch_days('hourlylmp/da/final', days, keep=at_pricing_location)

    # ── Shape ─────────────────────────────────────────────────────────────────

    df = to_frame([flatten_location(record) for record in records], COLUMNS).astype(dict.fromkeys(PRICES, 'float64'))
    if not df.empty:
        logging.info(f"Shaped {len(df)} rows: {df['BeginDate'].min()} to {df['BeginDate'].max()}")

    # ── Write ─────────────────────────────────────────────────────────────────

    append_to_bronze(df)
