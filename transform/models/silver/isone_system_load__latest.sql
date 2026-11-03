{#
  silver.isone_system_load__latest — one row per five-minute interval

  The newest version ISO-NE has published of each interval's load, with and
  without rooftop solar (see isone_system_load__base).

  Incremental: each run reads only ingest runs added since the last one
  (macros/new_ingest_runs.sql) and merges them in, replacing older versions of
  the same interval. The table grows ~105,000 rows a year. `dbt build
  --full-refresh` rebuilds it from all of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per interval among them (merged in on that
                         key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['interval_start_at'],
        cluster_by=['interval_start_at'],
        partition_by=monthly_partitions('interval_start_at'),
        incremental_predicates=recent_merge_window('interval_start_at')
    )
}}

WITH

    -- 1. Ingest runs not yet processed (all of bronze on a first build)
    new_runs AS (
        {{ new_ingest_runs(ref('isone_system_load__base')) }}
    )

-- 2. Newest version per interval (several runs may arrive at once)
SELECT
    interval_start_at,
    load_mw,
    native_load_mw,
    asset_related_demand_mw,
    load_with_btm_solar_mw,
    native_load_with_btm_solar_mw,
    btm_solar_mw,
    ingested_at,
    ingested_by
FROM new_runs
{{ keep_latest_version(['interval_start_at']) }}
