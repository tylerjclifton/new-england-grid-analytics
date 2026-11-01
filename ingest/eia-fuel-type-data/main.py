"""
Ingest: EIA-930 hourly net generation by fuel for ISO New England

Source:     EIA Open Data API, /electricity/rto/fuel-type-data (key; decision
            0014). One record per hour × fuel (fueltype): COL coal, NG natural
            gas, NUC nuclear, OIL petroleum, WAT hydro, PS pumped storage, SUN
            solar, SNB solar with battery, WND wind, BAT battery, OTH other.
            Hours are labelled by their UTC end (common/eia.py). A fuel not
            reported for an hour is null or absent, not 0.
Cadence:    Daily
Each run:   The last 14 days (LOOKBACK_DAYS), since EIA revises recent hours.
            A backfill (common/backfill.py) pulls a day range a month at a
            time; the API's history starts 2019-01-01 (the 2015 bulk files
            have no fuel breakdown, so there's no earlier source to add).
Writes to:  bronze.eia_fuel_type_data (append) — one row per hour × fuel × run

ISO-NE's own fuel mix (isone-fuel-mix) is finer and fresher; this is the
independent, hourly, revised record that lines up with EIA's demand series.
"""

# Import shared ingest helpers
from common.eia import fetch_hourly, hour_ranges, to_frame
from common.load import append_to_bronze

# Record fields under EIA's names, "-" written "_" (common/eia.py)
COLUMNS = ['period', 'respondent', 'respondent_name', 'fueltype', 'type_name', 'value', 'value_units']

# One range of hours at a time (a single range unless backfilling)
for start, end in hour_ranges():

    # ── Fetch ─────────────────────────────────────────────────────────────────

    records = fetch_hourly('fuel-type-data', start, end)

    # ── Shape and write ───────────────────────────────────────────────────────

    append_to_bronze(to_frame(records, COLUMNS))
