"""
Ingest: EIA-930 hourly demand, day-ahead demand forecast, net generation and
interchange for ISO New England

Source:     EIA Open Data API, /electricity/rto/region-data (key; decision
            0014). One record per hour × measure (type):
              D   Demand
              DF  Day-ahead demand forecast (ISO-NE's own)
              NG  Net generation
              TI  Total interchange (net exports; negative = importing)
            Hours are labelled by their UTC end (common/eia.py).
Cadence:    Daily
Each run:   The last 14 days (LOOKBACK_DAYS), since EIA revises recent hours.
            A backfill (common/backfill.py) pulls a day range a month at a
            time; the API's history starts 2019-01-01, and the bulk files
            cover 2015–2018 (eia-region-data-bulk).
Writes to:  bronze.eia_region_data (append) — one row per hour × measure × run
"""

# Import shared ingest helpers
from common.eia import fetch_hourly, hour_ranges, to_frame
from common.load import append_to_bronze

# Record fields under EIA's names, "-" written "_" (common/eia.py)
COLUMNS = ['period', 'respondent', 'respondent_name', 'type', 'type_name', 'value', 'value_units']

# One range of hours at a time (a single range unless backfilling)
for start, end in hour_ranges():

    # ── Fetch ─────────────────────────────────────────────────────────────────

    records = fetch_hourly('region-data', start, end)

    # ── Shape and write ───────────────────────────────────────────────────────

    append_to_bronze(to_frame(records, COLUMNS))
