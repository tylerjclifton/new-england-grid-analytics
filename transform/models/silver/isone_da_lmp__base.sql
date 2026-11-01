{#
  silver.isone_da_lmp__base — one row per hour × location × ingest run

  Every day-ahead price ISO-NE has published at the Hub and the eight load
  zones, renamed, with each location as the project's code (HUB, ME … NEMA).
  Day-ahead prices are final when published (decision 0012), so versions
  differ only by which run saw them; isone_da_lmp__latest keeps the newest.

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as isone_da_lmp__latest does). No tests here: they would scan all of
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
FROM {{ source('bronze', 'isone_da_lmp') }} AS prices
LEFT JOIN {{ ref('isone_pricing_locations') }} AS locations
    ON prices.`LocId` = locations.location_id
