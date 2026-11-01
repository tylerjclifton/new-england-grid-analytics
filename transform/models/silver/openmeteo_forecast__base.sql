{#
  silver.openmeteo_forecast__base — one row per load zone × hour × ingest run

  Every forecast Open-Meteo has given, renamed, typed, and converted to the
  units the grid uses. Unlike most __base models this keeps every version:
  for a forecast, each run is its own record (what was predicted, and when),
  not a revision to discard (decision 0009). Steps choose a version:
  openmeteo_forecast__latest takes the newest per hour.

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as openmeteo_forecast__latest does): the filter reaches bronze's partitions
  through the view. Tests live on the step tables, not here, because a test
  on this view would scan all of bronze every run (decision 0003).

  Steps:
    1. final select — rename to project conventions and convert units
                      (openmeteo_weather_columns macro, shared with the archive
                      and previous runs); lead time from run to hour
#}

SELECT
    load_zone,
    location_name,
    time                                                        AS hour_at,

    -- Hours from the run to the hour forecast; zero or negative means the
    -- hour had already passed (the model's best estimate, not a forecast)
    TIMESTAMP_DIFF(time, TIMESTAMP_TRUNC(ingested_at, HOUR), HOUR) AS lead_hours,

    -- °F, m/s, W/m², mm, cm (macros/openmeteo_weather_columns.sql)
    {{ openmeteo_weather_columns() }},

    latitude,
    longitude,
    ingested_at,
    ingested_by
FROM {{ source('bronze', 'openmeteo_forecast') }}
