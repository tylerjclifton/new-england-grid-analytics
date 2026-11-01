"""
Ingest: ISO-NE generation by fuel (the real-time fuel mix)

Source:     ISO-NE web services, /genfuelmix/day/{day} (ISO Express login;
            decision 0010). ISO-NE publishes a snapshot every few minutes, at
            irregular times (~200 a day): MW per fuel running at that moment,
            and which fuel is marginal (setting the price).
Cadence:    Every 6 hours
Each run:   Every snapshot for yesterday and today (Eastern days, see
            common/isone.py). The day files hold every snapshot, so polling
            less often loses nothing (decision 0003); re-pulling yesterday
            catches its last hours and any revision. A backfill pulls a day
            range instead, a month at a time (decision 0013).
Writes to:  bronze.isone_fuel_mix (append) — one row per snapshot × fuel × run

A fuel that isn't running is left out of a snapshot, not listed at 0 (oil
most of the year), so missing means zero; gold fills those in.
"""

# Import standard libraries
import logging

# Import shared ingest helpers
from common.isone import day_batches, fetch_days, to_frame
from common.load import append_to_bronze

# Record fields, kept under ISO-NE's names (bronze keeps the source's names)
COLUMNS = ['BeginDate', 'FuelCategory', 'FuelCategoryRollup', 'GenMw', 'MarginalFlag']

# One batch of days at a time (a single batch unless backfilling)
for days in day_batches():

    # ── Fetch ─────────────────────────────────────────────────────────────────

    records = fetch_days('genfuelmix', days)

    # ── Shape ─────────────────────────────────────────────────────────────────

    df = to_frame(records, COLUMNS).astype({'GenMw': 'float64'})
    if not df.empty:
        logging.info(f"Shaped {len(df)} rows: {df['BeginDate'].min()} to {df['BeginDate'].max()}")

    # ── Write ─────────────────────────────────────────────────────────────────

    append_to_bronze(df)
