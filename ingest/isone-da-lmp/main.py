"""
Ingest: ISO-NE hourly day-ahead prices (LMPs)

Source:     ISO-NE web services, /hourlylmp/da/final/day/{day}/location/{id}
            (ISO Express login; decision 0012). One call per day × pricing
            location: the Hub and the eight load zones (common/isone.py). The
            day-ahead market clears around midday for the next day, and its
            prices are final when published: the market's forecast of
            tomorrow's real-time prices.
Cadence:    Every 6 hours
Each run:   Today and tomorrow. Tomorrow is empty until the market clears, so
            the first run after it (18:10 Eastern) picks it up.
Writes to:  bronze.isone_da_lmp (append) — one row per hour × location × run
"""

# Import standard libraries
import logging

# Import shared ingest helpers
from common.isone import PRICING_LOCATIONS, eastern_days, fetch_days, flatten_location, to_frame
from common.load import append_to_bronze

# Record fields under ISO-NE's names (the location flattened by flatten_location)
PRICES  = ['LmpTotal', 'EnergyComponent', 'CongestionComponent', 'LossComponent']
COLUMNS = ['BeginDate', 'LocId', 'LocType', 'LocName', *PRICES]

# ── Fetch ─────────────────────────────────────────────────────────────────────

records = fetch_days('hourlylmp/da/final', eastern_days([0, 1]), PRICING_LOCATIONS)

# ── Shape ─────────────────────────────────────────────────────────────────────

df = to_frame([flatten_location(record) for record in records], COLUMNS).astype(dict.fromkeys(PRICES, 'float64'))
if not df.empty:
    logging.info(f"Shaped {len(df)} rows: {df['BeginDate'].min()} to {df['BeginDate'].max()}")

# ── Write ─────────────────────────────────────────────────────────────────────

append_to_bronze(df)
