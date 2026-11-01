{#
  silver.openmeteo_archive__base — one row per load zone × hour × ingest run

  Every reanalysis value Open-Meteo has given (decision 0015): the best
  estimate of what the weather was, from 2015-07, one point per ISO-NE load
  zone, renamed and in the same units as the forecast. Each daily run re-pulls
  two weeks, so an hour appears once per run that saw it;
  openmeteo_archive__latest keeps the newest.

  This is weather to explain what happened. A model predicting ahead trains
  on forecasts as issued instead (openmeteo_previous_runs__base, and
  openmeteo_forecast__base by lead_hours).

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as openmeteo_archive__latest does). No tests here: they would scan all of
  bronze (decision 0003).

  Steps:
    1. final select — rename and convert units (openmeteo_weather_columns)
#}

SELECT
    load_zone,
    location_name,
    time AS hour_at,

    -- °F, m/s, W/m², mm, cm (macros/openmeteo_weather_columns.sql)
    {{ openmeteo_weather_columns() }},

    latitude,
    longitude,
    ingested_at,
    ingested_by
FROM {{ source('bronze', 'openmeteo_archive') }}
