{#
  silver.isone_system_load__hourly — one row per hour

  ISO-NE's five-minute system load (isone_system_load__latest) averaged to the
  hour: MW averaged over the hour, which equals the hour's MWh. intervals says
  how many of the twelve five-minute intervals the hour had (fewer for the
  current hour, and in a backfill gap).

  A view over a silver table, read by gold (grid_hourly).

  Steps:
    1. final select — mean of each measure per UTC hour
#}

SELECT
    TIMESTAMP_TRUNC(interval_start_at, HOUR)  AS hour_start_at,
    AVG(load_mw)                              AS load_mw,
    AVG(native_load_mw)                       AS native_load_mw,
    AVG(btm_solar_mw)                         AS btm_solar_mw,
    AVG(load_with_btm_solar_mw)               AS load_with_btm_solar_mw,
    COUNT(*)                                  AS intervals
FROM {{ ref('isone_system_load__latest') }}
GROUP BY hour_start_at
