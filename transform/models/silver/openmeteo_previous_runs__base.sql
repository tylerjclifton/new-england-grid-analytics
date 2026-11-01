{#
  silver.openmeteo_previous_runs__base — one row per load zone × hour × lead × ingest run

  Past forecasts as they were issued, 1 and 2 days ahead (decision 0015),
  2021 to 2026-10-28, one point per ISO-NE load zone, renamed and in the same
  units as the forecast. Temperature throughout; the other variables are null
  before early 2024, when Open-Meteo starts keeping them. From 2026-10-29 the
  forecast job's snapshots carry on (openmeteo_forecast__base by lead_hours).

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as openmeteo_previous_runs__latest does). No tests here: they would scan
  all of bronze (decision 0003).

  Steps:
    1. final select — rename and convert units (openmeteo_weather_columns)
#}

SELECT
    load_zone,
    location_name,
    time AS hour_at,
    lead_days,

    -- °F, m/s, W/m², mm, cm (macros/openmeteo_weather_columns.sql)
    {{ openmeteo_weather_columns() }},

    latitude,
    longitude,
    ingested_at,
    ingested_by
FROM {{ source('bronze', 'openmeteo_previous_runs') }}
