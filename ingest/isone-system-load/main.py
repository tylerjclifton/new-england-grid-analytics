"""
Ingest: ISO-NE five-minute system load, with ISO-NE's rooftop solar estimate

Source:     ISO-NE web services, /fiveminutesystemload/day/{day} (ISO Express
            login; decision 0010). 288 intervals a day (300 on the day clocks
            fall back), each with:
              LoadMw           ISO-NE's system load: everything the grid serves
              NativeLoad       LoadMw less ArdDemand
              ArdDemand        asset-related demand: pumped storage pumping
                               and batteries charging
              SystemLoadBtmPv  LoadMw plus ISO-NE's estimate of behind-the-
                               meter (rooftop) solar, which the grid never
                               sees; equal to LoadMw after dark
              NativeLoadBtmPv  NativeLoad plus the same estimate
Cadence:    Every 6 hours
Each run:   Every interval for yesterday and today (Eastern days, see
            common/isone.py); re-pulling yesterday catches its last hours and
            any revision.
Writes to:  bronze.isone_system_load (append) — one row per interval × run
"""

# Import standard libraries
import logging

# Import shared ingest helpers
from common.isone import fetch_days, to_frame
from common.load import append_to_bronze

# Record fields, kept under ISO-NE's names (bronze keeps the source's names)
MEASURES = ['LoadMw', 'NativeLoad', 'ArdDemand', 'SystemLoadBtmPv', 'NativeLoadBtmPv']
COLUMNS  = ['BeginDate', *MEASURES]

# ── Fetch ─────────────────────────────────────────────────────────────────────

records = fetch_days('fiveminutesystemload')

# ── Shape ─────────────────────────────────────────────────────────────────────

df = to_frame(records, COLUMNS).astype(dict.fromkeys(MEASURES, 'float64'))
if not df.empty:
    logging.info(f"Shaped {len(df)} rows: {df['BeginDate'].min()} to {df['BeginDate'].max()}")

# ── Write ─────────────────────────────────────────────────────────────────────

append_to_bronze(df)
