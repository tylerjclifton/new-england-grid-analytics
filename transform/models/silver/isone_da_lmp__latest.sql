{#
  silver.isone_da_lmp__latest — one row per hour × location

  The day-ahead price for each hour at the Hub and each load zone: what the
  market expected the real-time price to be, set around midday the day before
  (decision 0012).

  Incremental: each run reads only ingest runs added since the last one
  (macros/new_ingest_runs.sql) and merges them in on hour × location. The table
  grows ~79,000 rows a year. `dbt build --full-refresh` rebuilds it from all of
  bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per hour × location among them (merged in
                         on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['hour_start_at', 'location_code'],
        cluster_by=['location_code', 'hour_start_at'],
        partition_by=monthly_partitions('hour_start_at'),
        incremental_predicates=recent_merge_window('hour_start_at')
    )
}}

WITH

    -- 1. Ingest runs not yet processed (all of bronze on a first build)
    new_runs AS (
        {{ new_ingest_runs(ref('isone_da_lmp__base')) }}
    )

-- 2. Newest version per hour × location (several runs may arrive at once)
SELECT
    hour_start_at,
    location_code,
    location_id,
    lmp_usd_mwh,
    energy_usd_mwh,
    congestion_usd_mwh,
    loss_usd_mwh,
    ingested_at,
    ingested_by
FROM new_runs
{{ keep_latest_version(['hour_start_at', 'location_code']) }}
