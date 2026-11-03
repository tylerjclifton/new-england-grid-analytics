{#
  silver.isone_zonal_load__latest — one row per five-minute interval × load zone

  The newest version ISO-NE has published of each zone's load in each interval,
  with and without rooftop solar (see isone_zonal_load__base).

  Incremental: each run reads only ingest runs added since the last one
  (macros/new_ingest_runs.sql) and merges them in, replacing older versions of
  the same interval × zone. The table grows ~840,000 rows a year. `dbt build
  --full-refresh` rebuilds it from all of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per interval × zone among them (merged in
                         on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['interval_start_at', 'load_zone'],
        cluster_by=['load_zone', 'interval_start_at'],
        partition_by=monthly_partitions('interval_start_at'),
        incremental_predicates=recent_merge_window('interval_start_at')
    )
}}

WITH

    -- 1. Ingest runs not yet processed (all of bronze on a first build)
    new_runs AS (
        {{ new_ingest_runs(ref('isone_zonal_load__base')) }}
    )

-- 2. Newest version per interval × zone (several runs may arrive at once)
SELECT
    interval_start_at,
    load_zone,
    load_zone_id,
    load_mw,
    btm_solar_mw,
    load_with_btm_solar_mw,
    ingested_at,
    ingested_by
FROM new_runs
{{ keep_latest_version(['interval_start_at', 'load_zone']) }}
