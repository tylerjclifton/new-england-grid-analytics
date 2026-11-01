"""
Ingest: EIA-930 hourly demand, day-ahead demand forecast, net generation and
interchange for ISO New England, 2015–2018, from EIA's bulk files — backfill only

Source:     EIA's six-month bulk files (no key), www.eia.gov/electricity/
            gridmonitor/sixMonthFiles/EIA930_BALANCE_<year>_<Jan_Jun|Jul_Dec>.csv,
            one row per balancing authority × hour, ~30–45 MB each, from
            2015_Jul_Dec (decision 0014). The API (eia-region-data) starts in
            2019; these files are the only source for the years before.
Cadence:    None. Run as a one-off backfill (BACKFILL_START / BACKFILL_END,
            common/backfill.py).
Each run:   Each six-month file overlapping the range: keep ISNE's rows in the
            range, and reshape its four measures into the API's long shape, so
            silver reads this table and eia_region_data the same way. The
            values match the API's where both exist (2019: "Demand (MW)" etc.
            equal the API's D, DF, NG, TI hour for hour).
Writes to:  bronze.eia_region_data_bulk (append) — one row per hour × measure × run
"""

# Import standard libraries
import io
import logging

# Import third party libraries
import pandas

# Import shared ingest helpers
from common.backfill import backfill_days, is_backfill
from common.fetch import fetch
from common.load import append_to_bronze
from common.run import fail

BULK_URL = 'https://www.eia.gov/electricity/gridmonitor/sixMonthFiles/EIA930_BALANCE_{year}_{half}.csv'

# Bulk column → the API's type code and name (eia-region-data)
MEASURES = {
    'Demand (MW)':            ('D',  'Demand'),
    'Demand Forecast (MW)':   ('DF', 'Day-ahead demand forecast'),
    'Net Generation (MW)':    ('NG', 'Net generation'),
    'Total Interchange (MW)': ('TI', 'Total interchange'),
}
TIME_COLUMN = 'UTC Time at End of Hour'  # e.g. "07/01/2015 5:00:00 AM"

# Output columns: the same as eia_region_data
COLUMNS = ['period', 'respondent', 'respondent_name', 'type', 'type_name', 'value', 'value_units']

# Backfill only: the API covers 2019 on, every day
if not is_backfill():
    fail("eia-region-data-bulk runs only as a backfill: set BACKFILL_START and BACKFILL_END (docs/runbook.md)")

days = backfill_days()
# The same hours the API's start/end would cover: periods 00:00 of the first
# day through 23:00 of the last (common/eia.py, hour_ranges)
first_hour = pandas.Timestamp(days[0], tz='UTC')
after_last = pandas.Timestamp(days[-1], tz='UTC') + pandas.Timedelta(days=1)

# Each six-month file overlapping the range, oldest first
halves = sorted({(day.year, 'Jan_Jun' if day.month <= 6 else 'Jul_Dec') for day in days})

for year, half in halves:

    # ── Fetch ─────────────────────────────────────────────────────────────────

    url = BULK_URL.format(year=year, half=half)
    content = fetch(url, timeout=300).content
    logging.info(f"Downloaded {url}: {len(content) / 1e6:.1f} MB")

    # ── Shape ─────────────────────────────────────────────────────────────────

    # Only the columns needed, as text; a renamed column fails here, loudly
    wide = pandas.read_csv(io.BytesIO(content), usecols=['Balancing Authority', TIME_COLUMN, *MEASURES], dtype=str)
    wide = wide[wide['Balancing Authority'] == 'ISNE']
    wide['period'] = pandas.to_datetime(wide[TIME_COLUMN], format='%m/%d/%Y %I:%M:%S %p', utc=True)
    wide = wide[(wide['period'] >= first_hour) & (wide['period'] < after_last)]

    # Wide → long, one row per hour × measure, in the API's shape
    df = wide.melt(id_vars='period', value_vars=list(MEASURES), var_name='column', value_name='value')
    df['type']      = df['column'].map(lambda column: MEASURES[column][0])
    df['type_name'] = df['column'].map(lambda column: MEASURES[column][1])
    df['value']     = pandas.to_numeric(df['value'].str.replace(',', ''), errors='raise').astype('float64')
    df = df.assign(respondent='ISNE', respondent_name='ISO New England', value_units='megawatthours')[COLUMNS]
    logging.info(f"Shaped {len(df)} rows: {df['period'].min()} to {df['period'].max()}")

    # ── Write ─────────────────────────────────────────────────────────────────

    append_to_bronze(df)
