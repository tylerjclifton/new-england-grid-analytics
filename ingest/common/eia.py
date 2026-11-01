"""
What every EIA ingest job shares: the EIA-930 API (the Hourly Electric Grid
Monitor) for ISO New England, its key, which hours to ask for, paging, and
shaping (decision 0014).

API: api.eia.gov/v2/electricity/rto/<dataset>/data, key in EIA_API_KEY (Secret
Manager, wired up in infra/cloud-run-jobs.tf), respondent ISNE. Records are
long, one per hour × measure, e.g.
  {"period": "2019-01-01T06", "respondent": "ISNE", "respondent-name": "ISO New England",
   "type": "D", "type-name": "Demand", "value": "11614", "value-units": "megawatthours"}
`period` is the UTC hour *ending* (it matches the bulk files' "UTC Time at End
of Hour"), and values come as strings. Responses page at PAGE_SIZE records.

A job using it, once per range of hours (hour_ranges(): one normally, a month
at a time in backfill mode, common/backfill.py):
  1. Fetch  → fetch_hourly('<dataset>', start, end): every record, all pages
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

API_URL    = 'https://api.eia.gov/v2/electricity/rto'
RESPONDENT = 'ISNE'
PAGE_SIZE  = 5000  # the API's maximum

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
    """Every ISNE record in `dataset` (region-data, fuel-type-data) from start to end, across pages."""
    api_key = os.getenv('EIA_API_KEY')
    if not api_key:
        fail("EIA_API_KEY must be set (the EIA Open Data key)")

    params = {
        'api_key':                api_key,
        'frequency':              'hourly',
        'data[0]':                'value',
        'facets[respondent][]':   RESPONDENT,
        'start':                  start,
        'sort[0][column]':        'period',
        'sort[0][direction]':     'asc',
        'length':                 PAGE_SIZE,
    }
    if end:
        params['end'] = end

    all_records = []
    while True:
        body = fetch(f"{API_URL}/{dataset}/data/", params={**params, 'offset': len(all_records)}).json()
        if 'response' not in body:
            fail(redact(f"EIA {dataset} returned no data: {str(body)[:500]}", [api_key]))
        page, total = body['response']['data'], int(body['response']['total'])
        all_records.extend(page)
        logging.info(f"{dataset} {start} to {end or 'latest'}: {len(all_records)} of {total} records")
        if not page or len(all_records) >= total:
            return all_records
        pause()


def to_frame(records, columns):
    """
    Records → a DataFrame of exactly `columns` (the API's names with "_" for
    "-", as BigQuery needs), period as a UTC TIMESTAMP and value as a float.

    Fails the job if any record lacks one of the columns: a changed API should
    stop the load, not quietly write nulls into bronze.
    """
    api_names = {column: column.replace('_', '-') for column in columns}
    missing = sorted({api for api in api_names.values() for record in records if api not in record})
    if missing:
        fail(f"EIA records are missing expected fields: {', '.join(missing)}")

    df = pandas.DataFrame([{column: record[api] for column, api in api_names.items()} for record in records],
                          columns=columns)
    df['period'] = pandas.to_datetime(df['period'], format='%Y-%m-%dT%H', utc=True)
    df['value']  = pandas.to_numeric(df['value']).astype('float64')
    return df
