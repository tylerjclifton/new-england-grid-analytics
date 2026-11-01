"""
Ingest: Open-Meteo hourly weather forecasts, one point per ISO-NE load zone

Source:     Open-Meteo forecast API (api.open-meteo.com, no key; free for
            non-commercial use within weighted limits). One request returns
            every point, in request order (common/openmeteo.py).
Cadence:    Every 6 hours
Each run:   Snapshots each point's hourly values from yesterday through 7 days
            ahead (PAST_DAYS + FORECAST_DAYS). Hours ahead are the forecast as
            of this run; past hours are the model's best estimate. Every run is
            kept, so silver can ask "what was forecast a day ahead?" and
            "what's the best estimate now?" (decision 0009).
Writes to:  bronze.openmeteo_forecast (append) — one row per load zone per hour
            per run

Values are kept in Open-Meteo's metric units; unit conversion happens in silver.
"""

# Import standard libraries
import logging
import os

# Import shared ingest helpers
from common.load import append_to_bronze
from common.openmeteo import HOURLY_VARIABLES, LOAD_ZONE_POINTS, fetch_points, to_frame

FORECAST_URL = 'https://api.open-meteo.com/v1/forecast'

# Snapshot window: yesterday's best estimate plus the week ahead
PAST_DAYS     = int(os.getenv('PAST_DAYS', '1'))
FORECAST_DAYS = int(os.getenv('FORECAST_DAYS', '7'))

# ── Fetch ─────────────────────────────────────────────────────────────────────

logging.info(f"Fetching Open-Meteo forecasts for {len(LOAD_ZONE_POINTS)} load zones")
points = fetch_points(FORECAST_URL, {
    'hourly':        ','.join(HOURLY_VARIABLES),
    'past_days':     PAST_DAYS,
    'forecast_days': FORECAST_DAYS,
})

# ── Shape ─────────────────────────────────────────────────────────────────────

df = to_frame(points, HOURLY_VARIABLES)
logging.info(f"Shaped {len(df)} rows: {df['time'].min()} to {df['time'].max()}")

# ── Write ─────────────────────────────────────────────────────────────────────

append_to_bronze(df)
