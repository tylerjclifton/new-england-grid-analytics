"""
Ingest: ISO-NE's seven-day wind power forecast

Source:     ISO-NE web services, /sevendaywindpowerforecast/day/{day} (ISO
            Express login; decision 0017). One forecast published each day
            (CreationDate, about 8:30 Eastern) for the rest of that day and
            the next seven: system-wide wind generation, MW, by market date
            (an Eastern day) and hour ending ("01"–"24"; "02X" is the repeated
            hour when clocks fall back, and the hour that doesn't exist when
            they spring forward is left out).
Cadence:    Every 6 hours
Each run:   The forecasts published yesterday and today. A backfill
            (common/backfill.py) pulls a day range, a month at a time.
Writes to:  bronze.isone_wind_forecast (append) — one row per publication ×
            hour × run

ISO-NE labels hours by market date and hour ending in Eastern time, so the
ingest also derives each hour's UTC start, BeginDate, like every other ISO-NE
table's. Each day's hours come in order and without gaps, so they're placed by
counting back from the day's last hour, whose end is never ambiguous: that
handles both clock changes without guessing what "02X" or a skipped hour means
(common/isone.py, hour_starts).
"""

# Import standard libraries
import datetime
import logging

# Import third party libraries
import pandas

# Import shared ingest helpers
from common.isone import day_batches, eastern_days, fetch_days, hour_starts
from common.load import append_to_bronze
from common.run import fail

COLUMNS = ['CreationDate', 'MarketDate', 'HourEnding', 'BeginDate', 'WindPowerForecast']


def to_rows(record):
    """One publication → one row per market day × hour, with the hour's UTC start."""
    rows = []
    for market_day in record['MarketDays']:
        hours = market_day['MarketDateInfo']['MarketDateData']
        hours = hours if isinstance(hours, list) else [hours]
        market_date = datetime.date.fromisoformat(market_day['MarketDate'][:10])
        endings = [hour['HourEnding'] for hour in hours]
        for hour, begin in zip(hours, hour_starts(market_date, endings), strict=True):
            rows.append({
                'CreationDate':      record['CreationDate'],
                'MarketDate':        market_date,
                'HourEnding':        hour['HourEnding'],
                'BeginDate':         begin,
                'WindPowerForecast': hour['WindPowerForecast'],
            })
    return rows


# One batch of days at a time (yesterday and today, unless backfilling)
for days in day_batches(eastern_days([-1, 0])):

    # ── Fetch ─────────────────────────────────────────────────────────────────

    records = fetch_days('sevendaywindpowerforecast', days)

    # ── Shape ─────────────────────────────────────────────────────────────────

    try:
        rows = [row for record in records for row in to_rows(record)]
    except (KeyError, TypeError) as error:
        fail(f"ISO-NE wind forecast records aren't in the expected shape: {error!r}")

    df = pandas.DataFrame(rows, columns=COLUMNS)
    df['CreationDate'] = pandas.to_datetime(df['CreationDate'], format='ISO8601', utc=True)
    df['BeginDate'] = pandas.to_datetime(df['BeginDate'], utc=True)
    df['WindPowerForecast'] = df['WindPowerForecast'].astype('float64')
    if not df.empty:
        logging.info(f"Shaped {len(df)} rows from {len(records)} forecasts: "
                     f"{df['BeginDate'].min()} to {df['BeginDate'].max()}")

    # ── Write ─────────────────────────────────────────────────────────────────

    append_to_bronze(df)
