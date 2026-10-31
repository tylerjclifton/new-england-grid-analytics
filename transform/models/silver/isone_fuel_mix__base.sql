{#
  silver.isone_fuel_mix__base — one row per snapshot × fuel × ingest run

  Every fuel mix snapshot ISO-NE has published, renamed and typed. Each ingest
  run re-pulls yesterday and today (decision 0010), so a snapshot appears once
  per run that saw it; isone_fuel_mix__latest keeps the newest version.

  A fuel that isn't running is absent from a snapshot, not listed at 0. This
  model keeps it that way; filling zeros is for gold.

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as isone_fuel_mix__latest does): the filter reaches bronze's partitions
  through the view. No tests here: they would scan all of bronze (decision 0003).

  ISO-NE's field names are backquoted: they're the source's CamelCase names
  (bronze keeps them, decision 0010), quoted to set them apart from ours.

  Steps:
    1. final select — rename to project conventions; MarginalFlag → boolean
#}

SELECT
    `BeginDate`           AS snapshot_at,
    `FuelCategory`        AS fuel,
    `FuelCategoryRollup`  AS fuel_group,
    `GenMw`               AS generation_mw,

    -- Whether this fuel was setting the real-time price at the snapshot
    `MarginalFlag` = 'Y'  AS is_marginal,

    ingested_at,
    ingested_by
FROM {{ source('bronze', 'isone_fuel_mix') }}
