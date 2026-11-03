{#
  silver.isone_load_forecast__base — one row per hour × version × ingest run

  Every version of ISO-NE's hourly system load forecast (decision 0017),
  renamed, with how far ahead each version was issued. Each run re-pulls
  yesterday and tomorrow, so a version appears once per run that saw it;
  isone_load_forecast__issued keeps each hour × version once.

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as isone_load_forecast__issued does). No tests here: they would scan all of
  bronze (decision 0003).

  ISO-NE's field names are backquoted: they're the source's CamelCase names
  (bronze keeps them, decision 0010), quoted to set them apart from ours.

  Steps:
    1. final select — rename; hours from issue to the hour forecast
#}

SELECT
    `BeginDate`                                          AS hour_start_at,
    `CreationDate`                                       AS issued_at,
    TIMESTAMP_DIFF(`BeginDate`, `CreationDate`, MINUTE) / 60  AS lead_hours,
    `LoadMw`                                             AS load_mw,
    `NetLoadMw`                                          AS net_load_mw,
    ingested_at,
    ingested_by
FROM {{ source('bronze', 'isone_load_forecast') }}
