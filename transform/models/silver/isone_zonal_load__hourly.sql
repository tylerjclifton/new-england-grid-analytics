{#
  silver.isone_zonal_load__hourly — one row per hour × load zone

  ISO-NE's five-minute zonal load (isone_zonal_load__latest) averaged to the
  hour, with and without the zone's rooftop solar. intervals says how many of
  the twelve five-minute intervals the hour had.

  A view over a silver table, read by gold (grid_zone_hourly).

  Steps:
    1. final select — mean of each measure per UTC hour and zone
#}

SELECT
    TIMESTAMP_TRUNC(interval_start_at, HOUR)  AS hour_start_at,
    load_zone,
    AVG(load_mw)                              AS load_mw,
    AVG(btm_solar_mw)                         AS btm_solar_mw,
    AVG(load_with_btm_solar_mw)               AS load_with_btm_solar_mw,
    COUNT(*)                                  AS intervals
FROM {{ ref('isone_zonal_load__latest') }}
GROUP BY hour_start_at, load_zone
