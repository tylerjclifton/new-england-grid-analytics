"""
What every Open-Meteo ingest job shares: the weather points (one per ISO-NE
load zone), the hourly variables, the request settings, and shaping a
multi-point response (decisions 0009, 0015).

Each job asks one of Open-Meteo's APIs for every point in one request
(comma-separated coordinates; the response lists points in request order):
  forecast       api.open-meteo.com/v1/forecast — the forecast now (openmeteo-forecast)
  archive        archive-api.open-meteo.com/v1/archive — reanalysis, the best
                 estimate of what happened (openmeteo-archive)
  previous runs  previous-runs-api.open-meteo.com/v1/forecast — past forecasts
                 as issued, by days ahead (openmeteo-previous-runs)

A job using it:
  1. Fetch  → fetch_points(url, params): every point's response, in order
  2. Shape  → to_frame(points, variables): one row per point × hour
  3. Write  → append_to_bronze(df)

Open-Meteo is free for non-commercial use within weighted limits (600 calls a
minute, 5,000 an hour, 10,000 a day; a call for many points, days or
variables counts as several), so backfills pause BACKFILL_PAUSE_SECONDS
between month-sized calls.
"""

# Import third party libraries
import pandas

# Import shared ingest helpers
from common.fetch import fetch

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

# A month for eight points is ~15–30 weighted calls; one every 6 s stays well
# under 600 a minute
BACKFILL_PAUSE_SECONDS = 6


def fetch_points(url, params):
    """Every load zone point's response from one Open-Meteo request, in LOAD_ZONE_POINTS order."""
    points = fetch(url, params={
        'latitude':        ','.join(str(lat) for _, _, lat, _ in LOAD_ZONE_POINTS),
        'longitude':       ','.join(str(lon) for _, _, _, lon in LOAD_ZONE_POINTS),
        'timezone':        'GMT',  # times come back in UTC (decision 0002)
        'wind_speed_unit': 'ms',   # m/s, the convention for wind power
        **params,
    }).json()

    # A single point comes back as an object, several as a list
    return [points] if isinstance(points, dict) else points


def to_frame(points, variables):
    """
    One row per point × hour: the point's load zone, city and grid cell, the
    hour (UTC), and each of `variables` (null where Open-Meteo has no value).
    Fails if the response has fewer points than were asked for (zip strict):
    zones can't be matched safely then.
    """
    frames = []
    for (load_zone, location_name, _, _), point in zip(LOAD_ZONE_POINTS, points, strict=True):
        hourly = point['hourly']
        frame = pandas.DataFrame({variable: hourly[variable] for variable in variables}, dtype='float64')
        frame.insert(0, 'time', pandas.to_datetime(hourly['time'], utc=True))
        frame.insert(0, 'elevation', point.get('elevation'))
        frame.insert(0, 'longitude', point['longitude'])
        frame.insert(0, 'latitude', point['latitude'])
        frame.insert(0, 'location_name', location_name)
        frame.insert(0, 'load_zone', load_zone)
        frames.append(frame)
    return pandas.concat(frames, ignore_index=True)
