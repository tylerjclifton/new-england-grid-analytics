{#
  silver.isone_zonal_load_forecast__base — one row per hour × zone × version × ingest run

  Every version of ISO-NE's hourly load forecast per load zone (decision 0017),
  renamed, with the zone as the project's code (ME … NEMA; ISO-NE names it like
  .Z.CONNECTICUT, matched through the isone_pricing_locations seed) and how far
  ahead each version was issued. isone_zonal_load_forecast__issued keeps each
  hour × zone × version once.

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as isone_zonal_load_forecast__issued does). No tests here: they would scan
  all of bronze (decision 0003).

  ISO-NE's field names are backquoted: they're the source's CamelCase names
  (bronze keeps them, decision 0010), quoted to set them apart from ours.

  Steps:
    1. final select — rename; zone name → code; hours from issue to the hour
#}

SELECT
    forecasts.`BeginDate`                                                 AS hour_start_at,
    locations.location_code                                               AS load_zone,
    forecasts.`CreationDate`                                              AS issued_at,
    TIMESTAMP_DIFF(forecasts.`BeginDate`, forecasts.`CreationDate`, MINUTE) / 60  AS lead_hours,
    forecasts.`LoadMw`                                                    AS load_mw,
    forecasts.`ReliabilityRegionLoadPercentage`                           AS share_of_system_pct,
    forecasts.ingested_at,
    forecasts.ingested_by
FROM {{ source('bronze', 'isone_zonal_load_forecast') }} AS forecasts
LEFT JOIN {{ ref('isone_pricing_locations') }} AS locations
    ON forecasts.`ReliabilityRegion` = locations.iso_location_name
