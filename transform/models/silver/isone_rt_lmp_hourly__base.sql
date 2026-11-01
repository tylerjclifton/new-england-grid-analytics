{#
  silver.isone_rt_lmp_hourly__base — one row per hour × location × ingest run

  Every hourly real-time price backfilled from ISO-NE (decision 0013): final
  prices for 2019–2024, before the five-minute history begins, at the Hub and
  the eight load zones, renamed, with each location as the project's code.
  Each hourly price is the mean of that hour's five-minute prices.

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as isone_rt_lmp_hourly__latest does). No tests here: they would scan all of
  bronze (decision 0003).

  ISO-NE's field names are backquoted: they're the source's CamelCase names
  (bronze keeps them, decision 0010), quoted to set them apart from ours.

  Steps:
    1. final select — rename; location ID → code (isone_pricing_locations seed)
#}

SELECT
    prices.`BeginDate`                AS hour_start_at,
    locations.location_code,
    prices.`LocId`                    AS location_id,
    prices.`LmpTotal`                 AS lmp_usd_mwh,
    prices.`EnergyComponent`          AS energy_usd_mwh,
    prices.`CongestionComponent`      AS congestion_usd_mwh,
    prices.`LossComponent`            AS loss_usd_mwh,
    prices.ingested_at,
    prices.ingested_by
FROM {{ source('bronze', 'isone_rt_lmp_hourly') }} AS prices
LEFT JOIN {{ ref('isone_pricing_locations') }} AS locations
    ON prices.`LocId` = locations.location_id
