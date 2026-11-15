"""
What every EIA ingest job shares: the EIA Open Data API, its key, paging, and
shaping; and for EIA-930 (the Hourly Electric Grid Monitor) for ISO New
England, which hours to ask for (decision 0014).

API: api.eia.gov/v2/<route>/data, key in EIA_API_KEY (Secret Manager, wired
up in infra/cloud-run-jobs.tf). Records are long, one per period × series or
measure, with values as strings. EIA-930's (route electricity/rto/<dataset>,
respondent ISNE) look like
  {"period": "2019-01-01T06", "respondent": "ISNE", "respondent-name": "ISO New England",
   "type": "D", "type-name": "Demand", "value": "11614", "value-units": "megawatthours"}
where `period` is the UTC hour *ending* (it matches the bulk files' "UTC Time
at End of Hour"). Natural gas prices (eia-natural-gas-prices, decision 0019)
come the same way, by day or month. Responses page at PAGE_SIZE records.

A job using it, once per query (for EIA-930, once per range of hours:
hour_ranges(), one normally, a month at a time in backfill mode,
common/backfill.py):
  1. Fetch  → fetch_records('<route>', params): every record, all pages
              (fetch_hourly('<dataset>', start, end) for EIA-930)
  2. Shape  → to_frame(records, COLUMNS): field names with "_" for "-",
              period in UTC, value as a number
  3. Write  → append_to_bronze(df)
"""

# Import standard libraries
import datetime
import logging
import os

# Import third party libraries
import pandas

# Import shared ingest helpers
from common.backfill import backfill_batches, is_backfill, pause
from common.fetch import fetch, redact
from common.run import fail

API_URL    = 'https://api.eia.gov/v2'
RESPONDENT = 'ISNE'
PAGE_SIZE  = 5000  # the API's maximum

# Record fields of each dataset, under EIA's names with "_" for "-" (to_frame).
# The bulk files are reshaped into the region data's (eia-region-data-bulk).
REGION_COLUMNS    = ['period', 'respondent', 'respondent_name', 'type', 'type_name', 'value', 'value_units']
FUEL_TYPE_COLUMNS = ['period', 'respondent', 'respondent_name', 'fueltype', 'type_name', 'value', 'value_units']

# Days per run, ending now. EIA revises recent hours (and regenerates its
# files daily), so each run re-pulls two weeks; bronze keeps every version.
LOOKBACK_DAYS = int(os.getenv('LOOKBACK_DAYS', '14'))


def hour_ranges(now=None):
    """
    The (start, end) hour ranges this run pulls, as the API's YYYY-MM-DDTHH
    (UTC, inclusive; end None = up to the latest). Normally one range: the last
    LOOKBACK_DAYS. In backfill mode, the backfill range a month at a time.
    """
    if is_backfill():
        return [(f"{batch[0]:%Y-%m-%d}T00", f"{batch[-1]:%Y-%m-%d}T23") for batch in backfill_batches()]
    now = now or datetime.datetime.now(datetime.timezone.utc)
    return [(f"{now - datetime.timedelta(days=LOOKBACK_DAYS):%Y-%m-%d}T00", None)]


def fetch_hourly(dataset, start, end=None):
    """Every ISNE record in EIA-930's `dataset` (region-data, fuel-type-data) from start to end."""
    params = {
        'frequency':            'hourly',
        'facets[respondent][]': RESPONDENT,
        'start':                start,
    }
    if end:
        params['end'] = end
    return fetch_records(f"electricity/rto/{dataset}", params)


def fetch_records(route, params):
    """
    Every record of `route` (e.g. electricity/rto/region-data) matching
    `params` (frequency, facets, start, end), oldest first, across pages. The
    key, the value field, sorting and paging are added here.
    """
    api_key = os.getenv('EIA_API_KEY')
    if not api_key:
        fail("EIA_API_KEY must be set (the EIA Open Data key)")

    params = {
        'api_key':            api_key,
        'data[0]':            'value',
        **params,
        'sort[0][column]':    'period',
        'sort[0][direction]': 'asc',
        'length':             PAGE_SIZE,
    }
    covers = f"{params.get('start', 'earliest')} to {params.get('end', 'latest')}"

    all_records = []
    while True:
        body = fetch(f"{API_URL}/{route}/data/", params={**params, 'offset': len(all_records)}).json()
        if 'response' not in body:
            fail(redact(f"EIA {route} returned no data: {str(body)[:500]}", [api_key]))
        page, total = body['response']['data'], int(body['response']['total'])
        all_records.extend(page)
        logging.info(f"{route} {covers}: {len(all_records)} of {total} records")
        if not page or len(all_records) >= total:
            return all_records
        pause()


def to_frame(records, columns, period_format='%Y-%m-%dT%H'):
    """
    Records → a DataFrame of exactly `columns` (the API's names with "_" for
    "-", as BigQuery needs), period as a UTC timestamp read with
    `period_format` (hours by default; '%Y-%m-%d' or '%Y-%m' for a daily or
    monthly series) and value as a float.

    Fails the job if any record lacks one of the columns: a changed API should
    stop the load, not quietly write nulls into bronze.
    """
    api_names = {column: column.replace('_', '-') for column in columns}
    missing = sorted({api for api in api_names.values() for record in records if api not in record})
    if missing:
        fail(f"EIA records are missing expected fields: {', '.join(missing)}")

    df = pandas.DataFrame([{column: record[api] for column, api in api_names.items()} for record in records],
                          columns=columns)
    df['period'] = pandas.to_datetime(df['period'], format=period_format, utc=True)
    df['value']  = pandas.to_numeric(df['value']).astype('float64')
    return df
