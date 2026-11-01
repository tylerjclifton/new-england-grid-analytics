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
  1. Fetch  → fetch_days('<feed>', days, locations): every record for each
              day and pricing location
  2. Shape  → to_frame(records, COLUMNS): one row per record, its time in UTC
              (price records first go through flatten_location())
  3. Write  → append_to_bronze(df)

Backfill mode (decision 0013): BACKFILL_START and BACKFILL_END (YYYYMMDD,
inclusive), set on a one-off execution, replace a job's usual days. Every batch
shares the run's ingested_at, so afterwards the affected silver models are
rebuilt with --full-refresh (docs/runbook.md, "Backfill a feed").
"""

# Import standard libraries
import datetime
import logging
import os
import time

# Import third party libraries
import pandas

# Import shared ingest helpers
from common.fetch import fetch
from common.run import fail

API_URL       = 'https://webservices.iso-ne.com/api/v1.1'
ISO_TIME_ZONE = 'America/New_York'

# Eastern days per run for the load and fuel mix feeds, ending today. Two
# re-pulls yesterday, which catches the intervals published after the previous
# day's last run (and any revision).
LOOKBACK_DAYS = int(os.getenv('LOOKBACK_DAYS', '2'))

# Backfill mode: the inclusive day range to pull instead (unset normally), how
# many days each batch loads, and a pause between calls to go easy on the API
BACKFILL_START         = os.getenv('BACKFILL_START')
BACKFILL_END           = os.getenv('BACKFILL_END')
BACKFILL_BATCH_DAYS    = 31
BACKFILL_PAUSE_SECONDS = 0.1

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


def is_backfill():
    """Whether this run is a backfill (BACKFILL_START / BACKFILL_END set)."""
    return bool(BACKFILL_START or BACKFILL_END)


def backfill_days():
    """Every day from BACKFILL_START to BACKFILL_END inclusive, as YYYYMMDD; fails the job on a bad range."""
    try:
        start, end = (datetime.datetime.strptime(day, '%Y%m%d') for day in (BACKFILL_START, BACKFILL_END))
    except (TypeError, ValueError):
        fail(f"BACKFILL_START and BACKFILL_END must both be YYYYMMDD days (got {BACKFILL_START!r}, {BACKFILL_END!r})")
    if start > end:
        fail(f"BACKFILL_START ({BACKFILL_START}) is after BACKFILL_END ({BACKFILL_END})")
    return [day.strftime('%Y%m%d') for day in pandas.date_range(start, end)]


def day_batches(days=None):
    """
    The days this run pulls, as batches to fetch and load one at a time.

    Normally that's `days` (default days_to_fetch()) as a single batch. In
    backfill mode it's the backfill range in batches of BACKFILL_BATCH_DAYS.
    """
    if not is_backfill():
        return [days or days_to_fetch()]
    all_days = backfill_days()
    logging.info(f"Backfill: {len(all_days)} days, {all_days[0]} to {all_days[-1]}")
    return [all_days[i:i + BACKFILL_BATCH_DAYS] for i in range(0, len(all_days), BACKFILL_BATCH_DAYS)]


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


def fetch_days(feed, days, locations=(None,)):
    """
    Every record `feed` has for each of `days`, oldest day first. A
    per-location feed (prices) takes `locations`, one call each.
    """
    username = os.getenv('ISONE_WS_USERNAME')
    password = os.getenv('ISONE_WS_PASSWORD')
    if not username or not password:
        fail("ISONE_WS_USERNAME and ISONE_WS_PASSWORD must be set (the ISO Express login)")

    all_records = []
    for day in days:
        for location in locations:
            path = f"{feed}/day/{day}" + (f"/location/{location}" if location else '')
            path_records = records(fetch(f"{API_URL}/{path}.json", auth=(username, password)).json())
            logging.info(f"{path}: {len(path_records)} records")
            all_records.extend(path_records)
            if is_backfill():
                time.sleep(BACKFILL_PAUSE_SECONDS)
    return all_records


def flatten_location(record):
    """
    A price record with its nested location flattened into LocId, LocType and
    LocName: {"Location": {"@LocId": "4000", "@LocType": "HUB",
    "$": ".H.INTERNAL_HUB"}} → LocId 4000, LocType "HUB", LocName ".H.INTERNAL_HUB".
    """
    flat = {key: value for key, value in record.items() if key != 'Location'}
    location = record['Location']
    return {**flat, 'LocId': int(location['@LocId']), 'LocType': location['@LocType'], 'LocName': location['$']}


def to_frame(records, columns, time_column='BeginDate'):
    """
    Records → a DataFrame of exactly `columns`, with `time_column` converted
    to UTC.

    Fails the job if any record lacks one of the columns: a changed API should
    stop the load, not quietly write nulls into bronze.
    """
    missing = sorted({column for record in records for column in columns if column not in record})
    if missing:
        fail(f"ISO-NE records are missing expected fields: {', '.join(missing)}")

    df = pandas.DataFrame(records, columns=columns)
    df[time_column] = pandas.to_datetime(df[time_column], format='ISO8601', utc=True)
    return df
