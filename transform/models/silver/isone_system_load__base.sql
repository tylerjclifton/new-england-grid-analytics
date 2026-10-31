{#
  silver.isone_system_load__base — one row per five-minute interval × ingest run

  Every five-minute system load interval ISO-NE has published, renamed, with
  ISO-NE's rooftop solar estimate broken out. Each ingest run re-pulls
  yesterday and today (decision 0010), so an interval appears once per run
  that saw it; isone_system_load__latest keeps the newest version.

  Two views of demand (both from ISO-NE):
    load_mw                 what the grid served (measured)
    load_with_btm_solar_mw  that plus rooftop solar the grid never sees: the
                            demand weather actually drives

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as isone_system_load__latest does). No tests here: they would scan all of
  bronze (decision 0003).

  ISO-NE's field names are backquoted: they're the source's CamelCase names
  (bronze keeps them, decision 0010), quoted to set them apart from ours.

  Steps:
    1. final select — rename to project conventions; rooftop solar as its own
                      column (the gap between the two loads)
#}

SELECT
    `BeginDate`                             AS interval_start_at,
    `LoadMw`                                AS load_mw,
    `NativeLoad`                            AS native_load_mw,
    `ArdDemand`                             AS asset_related_demand_mw,
    `SystemLoadBtmPv`                       AS load_with_btm_solar_mw,
    `NativeLoadBtmPv`                       AS native_load_with_btm_solar_mw,

    -- ISO-NE's behind-the-meter (rooftop) solar estimate; 0 after dark
    ROUND(`SystemLoadBtmPv` - `LoadMw`, 3)  AS btm_solar_mw,

    ingested_at,
    ingested_by
FROM {{ source('bronze', 'isone_system_load') }}
