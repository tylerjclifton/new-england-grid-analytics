"""
Ingest: ISO-NE hourly real-time prices (LMPs), final — backfill only

Source:     ISO-NE web services, /hourlylmp/rt/final/day/{day}/location/{id}
            (ISO Express login; decisions 0012, 0013). One call per day ×
            pricing location: the Hub and the eight load zones
            (common/isone.py). Each hourly price is the mean of that hour's
            twelve five-minute prices.
Cadence:    None. Run as a one-off backfill (BACKFILL_START / BACKFILL_END),
            for the years before ISO-NE's five-minute history begins (2024);
            from there on isone-rt-lmp's five-minute prices cover real time,
            and hourly is derived from them.
Each run:   Final prices for every day in the backfill range, a month at a time.
Writes to:  bronze.isone_rt_lmp_hourly (append) — one row per hour × location × run
"""

# Import standard libraries
import logging

# Import shared ingest helpers
from common.backfill import is_backfill
from common.isone import PRICING_LOCATIONS, day_batches, fetch_days, flatten_location, to_frame
from common.load import append_to_bronze
from common.run import fail

# Record fields under ISO-NE's names (the location flattened by flatten_location)
PRICES  = ['LmpTotal', 'EnergyComponent', 'CongestionComponent', 'LossComponent']
COLUMNS = ['BeginDate', 'LocId', 'LocType', 'LocName', *PRICES]

# Backfill only: a scheduled run would duplicate the five-minute feed
if not is_backfill():
    fail("isone-rt-lmp-hourly runs only as a backfill: set BACKFILL_START and BACKFILL_END (docs/runbook.md)")

# One batch of days at a time
for days in day_batches():

    # ── Fetch ─────────────────────────────────────────────────────────────────

    records = fetch_days('hourlylmp/rt/final', days, PRICING_LOCATIONS)

    # ── Shape ─────────────────────────────────────────────────────────────────

    df = to_frame([flatten_location(record) for record in records], COLUMNS).astype(dict.fromkeys(PRICES, 'float64'))
    if not df.empty:
        logging.info(f"Shaped {len(df)} rows: {df['BeginDate'].min()} to {df['BeginDate'].max()}")

    # ── Write ─────────────────────────────────────────────────────────────────

    append_to_bronze(df)
