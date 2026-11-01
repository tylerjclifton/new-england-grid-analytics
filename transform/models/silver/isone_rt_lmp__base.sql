{#
  silver.isone_rt_lmp__base — one row per five-minute interval × location × version × ingest run

  Every real-time price ISO-NE has published at the Hub and the eight load
  zones, renamed, with each location as the project's code (HUB, ME … NEMA).
  A price arrives as preliminary (within minutes), then as final (about a day
  later); is_final says which (decision 0012). isone_rt_lmp__latest keeps the
  final price where there is one.

  A price is energy + congestion + losses, all $/MWh: energy is the same
  everywhere in New England, so the spread between two locations is
  congestion and losses.

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as isone_rt_lmp__latest does). No tests here: they would scan all of
  bronze (decision 0003).

  ISO-NE's field names are backquoted: they're the source's CamelCase names
  (bronze keeps them, decision 0010), quoted to set them apart from ours.

  Steps:
    1. final select — rename; location ID → code (isone_pricing_locations
                      seed); LmpType → is_final
#}

SELECT
    prices.`BeginDate`                AS interval_start_at,
    locations.location_code,
    prices.`LocId`                    AS location_id,
    prices.`LmpTotal`                 AS lmp_usd_mwh,
    prices.`EnergyComponent`          AS energy_usd_mwh,
    prices.`CongestionComponent`      AS congestion_usd_mwh,
    prices.`LossComponent`            AS loss_usd_mwh,
    prices.`LmpType` = 'final'        AS is_final,
    prices.ingested_at,
    prices.ingested_by
FROM {{ source('bronze', 'isone_rt_lmp') }} AS prices
LEFT JOIN {{ ref('isone_pricing_locations') }} AS locations
    ON prices.`LocId` = locations.location_id
