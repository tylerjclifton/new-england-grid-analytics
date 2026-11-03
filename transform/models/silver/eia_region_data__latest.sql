{#
  silver.eia_region_data__latest — one row per hour × measure

  The newest value EIA has given for each hour of ISO New England's demand,
  day-ahead demand forecast, net generation and interchange (see
  eia_region_data__base). EIA revises recent hours, and each daily run re-pulls
  two weeks, so the newest version is EIA's current figure.

  Incremental: each run reads only ingest runs added since the last one
  (macros/new_ingest_runs.sql) and merges them in on hour × measure. The table
  grows ~35,000 rows a year (~400,000 back to 2015). `dbt build --full-refresh`
  rebuilds it from all of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per hour × measure among them (merged in
                         on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['hour_start_at', 'measure'],
        cluster_by=['measure', 'hour_start_at'],
        partition_by=monthly_partitions('hour_start_at'),
        incremental_predicates=recent_merge_window('hour_start_at')
    )
}}

WITH

    -- 1. Ingest runs not yet processed (all of bronze on a first build)
    new_runs AS (
        {{ new_ingest_runs(ref('eia_region_data__base')) }}
    )

-- 2. Newest version per hour × measure (several runs may arrive at once)
SELECT
    hour_start_at,
    measure,
    measure_name,
    value_mwh,
    source,
    ingested_at,
    ingested_by
FROM new_runs
{{ keep_latest_version(['hour_start_at', 'measure']) }}
