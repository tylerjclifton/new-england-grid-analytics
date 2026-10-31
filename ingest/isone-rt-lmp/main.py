"""
Ingest: ISO-NE five-minute real-time prices (LMPs), preliminary and final

Source:     ISO-NE web services, /fiveminutelmp/{prelim,final}/day/{day}/
            location/{id} (ISO Express login; decision 0012). One call per
            day × pricing location: the Hub and the eight load zones
            (common/isone.py). Each record is a five-minute interval's price,
            $/MWh, and its three parts: energy + congestion + losses.
Cadence:    Every 6 hours
Each run:   Preliminary prices for yesterday and today, as they're published
            (within minutes), and final prices for 2 and 3 days ago (finals
            follow about a day after the fact). The windows don't overlap, so
            a day is pulled as preliminary, then as final, never both in one
            run. LmpType records which version each row is.
Writes to:  bronze.isone_rt_lmp (append) — one row per interval × location ×
            version × run

Five-minute prices, not hourly: ISO-NE's hourly price is the mean of its
twelve five-minute prices, so silver or gold can derive it, while price
spikes that last minutes would be lost in an hourly feed.
"""

# Import standard libraries
import logging

# Import third party libraries
import pandas

# Import shared ingest helpers
from common.isone import PRICING_LOCATIONS, eastern_days, fetch_days, flatten_location, to_frame
from common.load import append_to_bronze

# Record fields under ISO-NE's names (the location flattened by flatten_location)
PRICES  = ['LmpTotal', 'EnergyComponent', 'CongestionComponent', 'LossComponent']
COLUMNS = ['BeginDate', 'LocId', 'LocType', 'LocName', *PRICES]

# Which days to pull as each version (offsets from today, Eastern)
DAYS_BY_LMP_TYPE = {
    'prelim': eastern_days([-1, 0]),   # published within minutes
    'final':  eastern_days([-3, -2]),  # published about a day after the fact
}

# ── Fetch and shape ───────────────────────────────────────────────────────────

# One frame per version, each row labelled with the version it is
frames = []
for lmp_type, days in DAYS_BY_LMP_TYPE.items():
    records = [flatten_location(record) for record in fetch_days(f'fiveminutelmp/{lmp_type}', days, PRICING_LOCATIONS)]
    frames.append(to_frame(records, COLUMNS).assign(LmpType=lmp_type))

df = pandas.concat(frames, ignore_index=True).astype(dict.fromkeys(PRICES, 'float64'))
if not df.empty:
    logging.info(f"Shaped {len(df)} rows: {df['BeginDate'].min()} to {df['BeginDate'].max()}")

# ── Write ─────────────────────────────────────────────────────────────────────

append_to_bronze(df)
