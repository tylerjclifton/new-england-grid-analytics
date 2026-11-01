{% macro openmeteo_weather_columns() -%}
  {#-
    The hourly weather columns of every Open-Meteo table (forecast, archive,
    previous runs; ingest/common/openmeteo.py), renamed to project conventions
    and converted to the units the grid uses: °C → °F (ISO-NE and degree-day
    convention), the rest named for their units. One definition, so the three
    tables' silver models line up column for column.

    Usage — in a select over an Open-Meteo bronze table:
      SELECT load_zone, time AS hour_at, {{ openmeteo_weather_columns() }}, ingested_at
      FROM {{ source('bronze', 'openmeteo_archive') }}
  -#}
    ROUND(temperature_2m * 9 / 5 + 32, 1)   AS temperature_f,
    ROUND(dew_point_2m * 9 / 5 + 32, 1)     AS dew_point_f,
    cloud_cover                             AS cloud_cover_pct,
    shortwave_radiation                     AS solar_irradiance_w_m2,
    wind_speed_10m                          AS wind_speed_10m_ms,
    wind_speed_100m                         AS wind_speed_100m_ms,
    precipitation                           AS precipitation_mm,
    snowfall                                AS snowfall_cm
{%- endmacro %}
