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
    1. final select — rename to project conventions; °C → °F (ISO-NE and
                      degree-day convention); lead time from run to hour
#}

SELECT
    load_zone,
    location_name,
    time                                                        AS hour_at,

    -- Hours from the run to the hour forecast; zero or negative means the
    -- hour had already passed (the model's best estimate, not a forecast)
    TIMESTAMP_DIFF(time, TIMESTAMP_TRUNC(ingested_at, HOUR), HOUR) AS lead_hours,

    ROUND(temperature_2m * 9 / 5 + 32, 1)                       AS temperature_f,
    ROUND(dew_point_2m * 9 / 5 + 32, 1)                         AS dew_point_f,
    cloud_cover                                                 AS cloud_cover_pct,
    shortwave_radiation                                         AS solar_irradiance_w_m2,
    wind_speed_10m                                              AS wind_speed_10m_ms,
    wind_speed_100m                                             AS wind_speed_100m_ms,
    precipitation                                               AS precipitation_mm,
    snowfall                                                    AS snowfall_cm,

    latitude,
    longitude,
    ingested_at,
    ingested_by
FROM {{ source('bronze', 'openmeteo_forecast') }}
