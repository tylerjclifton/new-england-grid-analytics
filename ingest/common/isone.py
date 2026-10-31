"""
What every ISO-NE ingest job shares: the web services API, its login, which
days to ask for, and unwrapping its responses (decision 0010).

ISO-NE's REST API (webservices.iso-ne.com/api/v1.1) takes HTTP basic auth with
an ISO Express login, read from ISONE_WS_USERNAME / ISONE_WS_PASSWORD (Secret
Manager, wired into each job in infra/cloud-run-jobs.tf). Feeds are fetched
one day at a time (/<feed>/day/YYYYMMDD.json, ISO-NE's days being Eastern).
Times come back in Eastern time with their UTC offset (e.g.
2026-10-30T12:00:00.000-04:00), so converting to UTC is exact through DST
changes (decision 0002).

A job using it:
  1. Fetch  → fetch_days('<feed>'): every record for each day in days_to_fetch()
  2. Shape  → to_frame(records, COLUMNS): one row per record, BeginDate in UTC
  3. Write  → append_to_bronze(df)
"""

# Import standard libraries
import datetime
import logging
import os

# Import third party libraries
import pandas

# Import shared ingest helpers
from common.fetch import fetch
from common.run import fail

API_URL       = 'https://webservices.iso-ne.com/api/v1.1'
ISO_TIME_ZONE = 'America/New_York'

# Eastern days per run, ending today. Two re-pulls yesterday, which catches the
# intervals published after the previous day's last run (and any revision).
LOOKBACK_DAYS = int(os.getenv('LOOKBACK_DAYS', '2'))


def days_to_fetch(today=None):
    """The last LOOKBACK_DAYS Eastern days, oldest first, as YYYYMMDD."""
    today = today or pandas.Timestamp.now(tz=ISO_TIME_ZONE).date()
    return [(today - datetime.timedelta(days=n)).strftime('%Y%m%d') for n in reversed(range(LOOKBACK_DAYS))]


def records(body):
    """
    The list of records in one response.

    ISO-NE wraps records twice, e.g. {"GenFuelMixes": {"GenFuelMix": [...]}}
    (a /current call, once). A day with no data comes back as
    {"GenFuelMixes": {}} or with an empty list, and a lone record may come
    back as an object rather than a one-item list.
    """
    content = next(iter(body.values()), None) if body else None
    if isinstance(content, dict):
        content = next(iter(content.values()), None)
    if not content:
        return []
    return content if isinstance(content, list) else [content]


def fetch_days(feed):
    """Every record `feed` has for each day in days_to_fetch(), oldest day first."""
    username = os.getenv('ISONE_WS_USERNAME')
    password = os.getenv('ISONE_WS_PASSWORD')
    if not username or not password:
        fail("ISONE_WS_USERNAME and ISONE_WS_PASSWORD must be set (the ISO Express login)")

    all_records = []
    for day in days_to_fetch():
        day_records = records(fetch(f"{API_URL}/{feed}/day/{day}.json", auth=(username, password)).json())
        logging.info(f"{feed} {day}: {len(day_records)} records")
        all_records.extend(day_records)
    return all_records


def to_frame(records, columns):
    """
    Records → a DataFrame of exactly `columns`, with BeginDate converted to UTC.

    Fails the job if any record lacks one of the columns: a changed API should
    stop the load, not quietly write nulls into bronze.
    """
    missing = sorted({column for record in records for column in columns if column not in record})
    if missing:
        fail(f"ISO-NE records are missing expected fields: {', '.join(missing)}")

    df = pandas.DataFrame(records, columns=columns)
    df['BeginDate'] = pandas.to_datetime(df['BeginDate'], format='ISO8601', utc=True)
    return df
