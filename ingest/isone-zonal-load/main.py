"""
Ingest: ISO-NE five-minute estimated load per load zone, with rooftop solar

Source:     ISO-NE web services, /fiveminuteestimatedzonalload/day/{day} (ISO
            Express login; decision 0010). 288 intervals × 8 load zones a day,
            each with:
              estimated_load_mw    the zone's estimated load; the eight zones
                                   add up to system native load
              estimated_btm_pv_mw  the zone's behind-the-meter (rooftop)
                                   solar estimate; the zones add up to the
                                   system estimate in isone_system_load
            This feed uses snake_case field names, unlike most ISO-NE feeds.
Cadence:    Every 6 hours
Each run:   Every interval for yesterday and today (Eastern days, see
            common/isone.py); re-pulling yesterday catches its last hours and
            any revision. A backfill pulls a day range instead, a month at a
            time (decision 0013).
Writes to:  bronze.isone_zonal_load (append) — one row per interval × load
            zone × run
"""

# Import standard libraries
import logging

# Import shared ingest helpers
from common.isone import day_batches, fetch_days, to_frame
from common.load import append_to_bronze

# Record fields, kept under ISO-NE's names (bronze keeps the source's names)
MEASURES = ['estimated_load_mw', 'estimated_btm_pv_mw']
COLUMNS  = ['interval_begin_date', 'load_zone_id', 'load_zone_name', *MEASURES]

# One batch of days at a time (a single batch unless backfilling)
for days in day_batches():

    # ── Fetch ─────────────────────────────────────────────────────────────────

    records = fetch_days('fiveminuteestimatedzonalload', days)

    # ── Shape ─────────────────────────────────────────────────────────────────

    df = (
        to_frame(records, COLUMNS, time_column='interval_begin_date')
        .astype({'load_zone_id': 'int64', **dict.fromkeys(MEASURES, 'float64')})
    )
    if not df.empty:
        logging.info(f"Shaped {len(df)} rows: {df['interval_begin_date'].min()} to {df['interval_begin_date'].max()}")

    # ── Write ─────────────────────────────────────────────────────────────────

    append_to_bronze(df)
