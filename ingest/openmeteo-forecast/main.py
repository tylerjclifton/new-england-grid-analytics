"""
Ingest: Open-Meteo hourly weather forecasts, one point per ISO-NE load zone

Source:     Open-Meteo forecast API (api.open-meteo.com, no key; free for
            non-commercial use, 10,000 calls/day). One request returns every
            point, in request order.
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

# Import third party libraries
import pandas

# Import shared ingest helpers
from common.fetch import fetch
from common.load import append_to_bronze

FORECAST_URL = 'https://api.open-meteo.com/v1/forecast'

# One point per ISO-NE load zone, at its largest population center (where
# demand is; decision 0009). Zone IDs follow ISO-NE's load zone names.
LOAD_ZONE_POINTS = [
    # load_zone, location_name, latitude, longitude
    ('ME',   'Portland',   43.66, -70.26),
    ('NH',   'Manchester', 42.99, -71.46),
    ('VT',   'Burlington', 44.48, -73.21),
    ('CT',   'Hartford',   41.76, -72.69),
    ('RI',   'Providence', 41.82, -71.41),
    ('SEMA', 'Brockton',   42.08, -71.02),
    ('WCMA', 'Worcester',  42.26, -71.80),
    ('NEMA', 'Boston',     42.36, -71.06),
]

# Hourly variables requested; each becomes a bronze column of the same name
HOURLY_VARIABLES = [
    'temperature_2m',       # load: heating and cooling
    'dew_point_2m',         # load: humidity drives summer cooling
    'cloud_cover',          # solar
    'shortwave_radiation',  # solar (irradiance)
    'wind_speed_10m',
    'wind_speed_100m',      # wind generation (turbine hub height)
    'precipitation',
    'snowfall',             # storms, outages
]

# Snapshot window: yesterday's best estimate plus the week ahead
PAST_DAYS     = int(os.getenv('PAST_DAYS', '1'))
FORECAST_DAYS = int(os.getenv('FORECAST_DAYS', '7'))

# ── Fetch ─────────────────────────────────────────────────────────────────────

params = {
    'latitude':        ','.join(str(lat) for _, _, lat, _ in LOAD_ZONE_POINTS),
    'longitude':       ','.join(str(lon) for _, _, _, lon in LOAD_ZONE_POINTS),
    'hourly':          ','.join(HOURLY_VARIABLES),
    'past_days':       PAST_DAYS,
    'forecast_days':   FORECAST_DAYS,
    'timezone':        'GMT',  # times come back in UTC (decision 0002)
    'wind_speed_unit': 'ms',   # m/s, the convention for wind power
}

logging.info(f"Fetching Open-Meteo forecasts for {len(LOAD_ZONE_POINTS)} load zones")
points = fetch(FORECAST_URL, params=params).json()

# A single point comes back as an object, several as a list
if isinstance(points, dict):
    points = [points]

# ── Shape ─────────────────────────────────────────────────────────────────────

# One frame per point: its hourly arrays become columns, one row per hour
frames = []
for (load_zone, location_name, _, _), point in zip(LOAD_ZONE_POINTS, points, strict=True):
    hourly = point['hourly']
    frame = pandas.DataFrame({variable: hourly[variable] for variable in HOURLY_VARIABLES}, dtype='float64')
    frame.insert(0, 'time', pandas.to_datetime(hourly['time'], utc=True))
    frame.insert(0, 'elevation', point.get('elevation'))
    frame.insert(0, 'longitude', point['longitude'])
    frame.insert(0, 'latitude', point['latitude'])
    frame.insert(0, 'location_name', location_name)
    frame.insert(0, 'load_zone', load_zone)
    frames.append(frame)

df = pandas.concat(frames, ignore_index=True)
logging.info(f"Shaped {len(df)} rows: {df['time'].min()} to {df['time'].max()}")

# ── Write ─────────────────────────────────────────────────────────────────────

append_to_bronze(df)
