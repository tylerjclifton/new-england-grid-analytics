{#
  silver.isone_fuel_mix__latest — one row per snapshot × fuel

  The newest version ISO-NE has published of each snapshot: what was running,
  how much, and which fuel was marginal. Fuels not running are absent (see
  isone_fuel_mix__base).

  Incremental: each run reads only ingest runs added since the last one
  (macros/new_ingest_runs.sql) and merges them in, replacing older versions of
  the same snapshot × fuel. The table grows ~700,000 rows a year. `dbt build
  --full-refresh` rebuilds it from all of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per snapshot × fuel among them (merged in
                         on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['snapshot_at', 'fuel'],
        cluster_by=['fuel', 'snapshot_at'],
        partition_by=monthly_partitions('snapshot_at'),
        incremental_predicates=recent_merge_window('snapshot_at')
    )
}}

WITH

    -- 1. Ingest runs not yet processed (all of bronze on a first build)
    new_runs AS (
        {{ new_ingest_runs(ref('isone_fuel_mix__base')) }}
    )

-- 2. Newest version per snapshot × fuel (several runs may arrive at once)
SELECT
    snapshot_at,
    fuel,
    fuel_group,
    generation_mw,
    is_marginal,
    ingested_at,
    ingested_by
FROM new_runs
{{ keep_latest_version(['snapshot_at', 'fuel']) }}
