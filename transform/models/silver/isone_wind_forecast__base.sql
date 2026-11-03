{#
  silver.isone_wind_forecast__base — one row per publication × hour × ingest run

  Every hour of every seven-day wind power forecast ISO-NE has published
  (decision 0017), renamed, with how far ahead it was issued. The hour's UTC
  start was derived by the ingest from ISO-NE's market date and hour ending
  (ingest/common/isone.py, hour_starts). isone_wind_forecast__issued keeps
  each hour × publication once.

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as isone_wind_forecast__issued does). No tests here: they would scan all of
  bronze (decision 0003).

  ISO-NE's field names are backquoted: they're the source's CamelCase names
  (bronze keeps them, decision 0010), quoted to set them apart from ours.

  Steps:
    1. final select — rename; hours from publication to the hour
#}

SELECT
    `BeginDate`                                               AS hour_start_at,
    `CreationDate`                                            AS issued_at,
    TIMESTAMP_DIFF(`BeginDate`, `CreationDate`, MINUTE) / 60  AS lead_hours,
    `WindPowerForecast`                                       AS wind_mw,
    `MarketDate`                                              AS market_date,
    `HourEnding`                                              AS hour_ending,
    ingested_at,
    ingested_by
FROM {{ source('bronze', 'isone_wind_forecast') }}
