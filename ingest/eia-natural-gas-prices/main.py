"""
Ingest: natural gas prices — the Henry Hub spot price every trading day, and
what New England's power plants paid for gas, monthly by state

Source:     EIA Open Data API (key; decision 0019), two routes with the same
            record fields:
              natural-gas/pri/fut  daily    series RNGWHHD: the Henry Hub spot
                                            price, $/MMBtu, trading days only
              natural-gas/pri/sum  monthly  process PEU: the price of gas
                                            delivered to electric power
                                            consumers, $/MCF, for each New
                                            England state (null where EIA
                                            withholds it)
Cadence:    Daily
Each run:   Each series' last LOOKBACK_DAYS: a month of the daily one (EIA
            posts it about weekly), two years of the monthly one (published
            about two months after the month, and revised for up to two years).
            A backfill (common/backfill.py) pulls its range in one query per
            series, from 2015.
Writes to:  bronze.eia_natural_gas_prices (append) — one row per series × period × run
"""

# Import standard libraries
import datetime

# Import shared ingest helpers
from common.backfill import backfill_days, is_backfill
from common.eia import fetch_records, to_frame
from common.load import append_to_bronze

# Both routes' record fields (common/eia.py, to_frame); the shaping adds
# `frequency` after period, so a row says which kind of series it's from
COLUMNS = ['period', 'duoarea', 'area_name', 'product', 'product_name', 'process', 'process_name',
           'series', 'series_description', 'value', 'units']

NEW_ENGLAND_STATES = ['CT', 'MA', 'ME', 'NH', 'RI', 'VT']

# One query per series: route, frequency, the API's period format (for the
# range asked for and for reading the answer), facets, and days re-pulled
QUERIES = [
    ('natural-gas/pri/fut', 'daily', '%Y-%m-%d',
     {'facets[series][]': ['RNGWHHD']}, 30),
    ('natural-gas/pri/sum', 'monthly', '%Y-%m',
     {'facets[process][]': ['PEU'], 'facets[duoarea][]': [f"S{state}" for state in NEW_ENGLAND_STATES]}, 731),
]

today = datetime.datetime.now(datetime.timezone.utc).date()

for route, frequency, period_format, facets, lookback_days in QUERIES:

    # ── Fetch ─────────────────────────────────────────────────────────────────

    # The backfill range, or the series' lookback up to the latest
    if is_backfill():
        days = backfill_days()
        period_range = {'start': f"{days[0]:{period_format}}", 'end': f"{days[-1]:{period_format}}"}
    else:
        period_range = {'start': f"{today - datetime.timedelta(days=lookback_days):{period_format}}"}
    records = fetch_records(route, {'frequency': frequency, **facets, **period_range})

    # ── Shape ─────────────────────────────────────────────────────────────────

    # Period as a date: the trading day, or the month's first day
    df = to_frame(records, COLUMNS, period_format)
    df['period'] = df['period'].dt.date
    df.insert(1, 'frequency', frequency)

    # ── Write ─────────────────────────────────────────────────────────────────

    append_to_bronze(df, time_column='period')
