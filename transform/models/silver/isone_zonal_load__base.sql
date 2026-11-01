{#
  silver.isone_zonal_load__base — one row per five-minute interval × load zone × ingest run

  Every zonal load interval ISO-NE has published, renamed, with the load zone
  as the project's code (ME … NEMA, matching the weather; decision 0009). Each
  ingest run re-pulls yesterday and today (decision 0010), so an interval
  appears once per run that saw it; isone_zonal_load__latest keeps the newest.

  Two views of each zone's demand (both from ISO-NE):
    load_mw                 the zone's estimated load (the zones add up to
                            system native load)
    load_with_btm_solar_mw  that plus the zone's rooftop solar estimate

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as isone_zonal_load__latest does): the filter reaches bronze's partitions
  through the view. No tests here: they would scan all of bronze (decision 0003).

  Steps:
    1. final select — rename; load zone ID → code (isone_pricing_locations
                      seed); rooftop solar added back to load
#}

SELECT
    zonal.interval_begin_date                                    AS interval_start_at,
    locations.location_code                                      AS load_zone,
    zonal.load_zone_id,
    zonal.estimated_load_mw                                      AS load_mw,
    zonal.estimated_btm_pv_mw                                    AS btm_solar_mw,
    ROUND(zonal.estimated_load_mw + zonal.estimated_btm_pv_mw, 3) AS load_with_btm_solar_mw,
    zonal.ingested_at,
    zonal.ingested_by
FROM {{ source('bronze', 'isone_zonal_load') }} AS zonal
LEFT JOIN {{ ref('isone_pricing_locations') }} AS locations
    ON zonal.load_zone_id = locations.location_id
