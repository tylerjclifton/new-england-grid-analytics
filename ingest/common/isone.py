"""
What every ISO-NE ingest job shares: the web services API, its login, which
days and pricing locations to ask for, backfill mode, and unwrapping its
responses (decisions 0010, 0012, 0013).

ISO-NE's REST API (webservices.iso-ne.com/api/v1.1) takes HTTP basic auth with
an ISO Express login, read from ISONE_WS_USERNAME / ISONE_WS_PASSWORD (Secret
Manager, wired into each job in infra/cloud-run-jobs.tf). Feeds are fetched
one day at a time (/<feed>/day/YYYYMMDD[/location/<id>].json, ISO-NE's days
being Eastern). Times come back in Eastern time with their UTC offset (e.g.
2026-10-30T12:00:00.000-04:00), so converting to UTC is exact through DST
changes (decision 0002).

A job using it, once per batch of days (day_batches(): one batch normally,
~monthly batches in backfill mode, so memory stays flat):
  1. Fetch  → fetch_days('<feed>', days, locations, keep): every record for
              each day (and pricing location, for feeds served per location;
              or kept by `keep`, for feeds served for every location at once)
  2. Shape  → to_frame(records, COLUMNS): one row per record, its time in UTC
              (price records first go through flatten_location())
  3. Write  → append_to_bronze(df)

Backfill mode (common/backfill.py, decision 0013) replaces a job's usual days
with a day range, batched by month.
"""

# Import standard libraries
import datetime
import logging
import os
from zoneinfo import ZoneInfo

# Import third party libraries
import pandas

# Import shared ingest helpers
from common.backfill import backfill_batches, is_backfill, pause
from common.fetch import fetch
from common.run import fail

API_URL       = 'https://webservices.iso-ne.com/api/v1.1'
ISO_TIME_ZONE = 'America/New_York'

# Eastern days per run for the load and fuel mix feeds, ending today. Two
# re-pulls yesterday, which catches the intervals published after the previous
# day's last run (and any revision).
LOOKBACK_DAYS = int(os.getenv('LOOKBACK_DAYS', '2'))

# Pricing locations the price jobs ask for (decision 0012): the Hub and the
# eight load zones, whose IDs match the zonal load feed's load_zone_id.
# Their meaning (which load zone each is) lives in silver, not here.
PRICING_LOCATIONS = [
    4000,  # .H.INTERNAL_HUB — the Hub, New England's benchmark price
    4001,  # .Z.MAINE
    4002,  # .Z.NEWHAMPSHIRE
    4003,  # .Z.VERMONT
    4004,  # .Z.CONNECTICUT
    4005,  # .Z.RHODEISLAND
    4006,  # .Z.SEMASS
    4007,  # .Z.WCMASS
    4008,  # .Z.NEMASSBOST
]


def eastern_days(offsets, today=None):
    """Eastern days at these offsets from today (-1 = yesterday, 1 = tomorrow), as YYYYMMDD."""
    today = today or pandas.Timestamp.now(tz=ISO_TIME_ZONE).date()
    return [(today + datetime.timedelta(days=offset)).strftime('%Y%m%d') for offset in offsets]


def days_to_fetch(today=None):
    """The last LOOKBACK_DAYS Eastern days, oldest first, as YYYYMMDD."""
    return eastern_days(range(1 - LOOKBACK_DAYS, 1), today=today)


def day_batches(days=None):
    """
    The days this run pulls (YYYYMMDD), as batches to fetch and load one at a time.

    Normally that's `days` (default days_to_fetch()) as a single batch. In
    backfill mode it's the backfill range, a month at a time.
    """
    if not is_backfill():
        return [days or days_to_fetch()]
    return [[day.strftime('%Y%m%d') for day in batch] for batch in backfill_batches()]


def hour_starts(market_date, hour_endings):
    """
    The UTC start of each hour in one market day's list of hours ending, in
    order (feeds that label hours by Eastern market date and hour ending,
    "01"–"24", with "02X" for the repeated hour when clocks fall back).

    The list is contiguous, so its last entry's end, an ordinary local time
    (hour ending 24, or the last hour of a partial day, never during a clock
    change), anchors it, and each earlier entry is one hour before the next.
    That handles both clock changes without interpreting "02X" or a skipped
    hour.
    """
    last_end_local = datetime.datetime.combine(market_date, datetime.time()) \
        + datetime.timedelta(hours=int(hour_endings[-1][:2]))
    last_end = last_end_local.replace(tzinfo=ZoneInfo(ISO_TIME_ZONE)).astimezone(datetime.timezone.utc)
    count = len(hour_endings)
    return [last_end - datetime.timedelta(hours=count - position) for position in range(count)]


def records(body):
    """
    The list of records in one response.

    ISO-NE wraps records in one to three single-key objects, depending on the
    feed: {"GenFuelMixes": {"GenFuelMix": [...]}}, or
    {"isone_web_services": {"five_min_estimated_zonal_loads":
    {"five_min_estimated_zonal_load": [...]}}}. A day with no data comes back
    with an empty object or an empty list at any of those levels, and a lone
    record may come back as an object rather than a one-item list.
    """
    content = body
    while isinstance(content, dict) and len(content) == 1:
        content = next(iter(content.values()))
    if not content:
        return []
    return content if isinstance(content, list) else [content]


def fetch_days(feed, days, locations=(None,), keep=None, suffix=''):
    """
    Every record `feed` has for each of `days`, oldest day first. A feed served
    per location (five-minute prices) takes `locations`, one call each. For a
    feed served for every location at once (hourly prices, ~1,200 locations a
    day), `keep` filters each call's records as they arrive (e.g.
    at_pricing_location), so only the kept ones are held in memory. `suffix`
    goes after the day, for feeds with one (e.g. '/all' for every version).
    """
    username = os.getenv('ISONE_WS_USERNAME')
    password = os.getenv('ISONE_WS_PASSWORD')
    if not username or not password:
        fail("ISONE_WS_USERNAME and ISONE_WS_PASSWORD must be set (the ISO Express login)")

    all_records = []
    for day in days:
        for location in locations:
            path = f"{feed}/day/{day}{suffix}" + (f"/location/{location}" if location else '')
            path_records = records(fetch(f"{API_URL}/{path}.json", auth=(username, password)).json())
            if keep:
                path_records = [record for record in path_records if keep(record)]
            logging.info(f"{path}: {len(path_records)} records")
            all_records.extend(path_records)
            pause()
    return all_records


def at_pricing_location(record):
    """Whether a price record is at one of PRICING_LOCATIONS (for fetch_days' `keep`)."""
    return int(record['Location']['@LocId']) in PRICING_LOCATIONS


def flatten_location(record):
    """
    A price record with its nested location flattened into LocId, LocType and
    LocName: {"Location": {"@LocId": "4000", "@LocType": "HUB",
    "$": ".H.INTERNAL_HUB"}} → LocId 4000, LocType "HUB", LocName ".H.INTERNAL_HUB".
    """
    flat = {key: value for key, value in record.items() if key != 'Location'}
    location = record['Location']
    return {**flat, 'LocId': int(location['@LocId']), 'LocType': location['@LocType'], 'LocName': location['$']}


def to_frame(records, columns, time_columns=('BeginDate',)):
    """
    Records → a DataFrame of exactly `columns`, with each of `time_columns`
    converted to UTC.

    Fails the job if any record lacks one of the columns: a changed API should
    stop the load, not quietly write nulls into bronze.
    """
    missing = sorted({column for record in records for column in columns if column not in record})
    if missing:
        fail(f"ISO-NE records are missing expected fields: {', '.join(missing)}")

    df = pandas.DataFrame(records, columns=columns)
    for column in time_columns:
        df[column] = pandas.to_datetime(df[column], format='ISO8601', utc=True)
    return df
