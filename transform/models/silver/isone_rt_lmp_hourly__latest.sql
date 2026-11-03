{#
  silver.isone_rt_lmp_hourly__latest — one row per hour × location

  The final hourly real-time price for each hour of 2019–2024 at the Hub and
  each load zone (decision 0013). From 2024 on, hourly real-time prices are
  derived from the five-minute feed (isone_rt_lmp__latest) instead; the
  months in both check that derivation.

  Incremental: each run reads only ingest runs added since the last one
  (macros/new_ingest_runs.sql) and merges them in on hour × location. It's a
  one-off backfill, so the table holds ~480,000 rows and grows only if the
  backfill is re-run. `dbt build --full-refresh` rebuilds it from all of
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
        {{ new_ingest_runs(ref('isone_rt_lmp_hourly__base')) }}
    )

-- 2. Newest version per hour × location
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
