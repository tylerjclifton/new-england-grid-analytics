{#
  silver.eia_fuel_type_data__latest — one row per hour × fuel

  The newest value EIA has given for each hour's generation from each fuel in
  ISO New England (see eia_fuel_type_data__base).

  Incremental: each run reads only ingest runs added since the last one
  (macros/new_ingest_runs.sql) and merges them in on hour × fuel. The table
  grows ~95,000 rows a year. `dbt build --full-refresh` rebuilds it from all of
  bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per hour × fuel among them (merged in on
                         that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['hour_start_at', 'fuel'],
        cluster_by=['fuel', 'hour_start_at'],
        partition_by=monthly_partitions('hour_start_at'),
        incremental_predicates=recent_merge_window('hour_start_at')
    )
}}

WITH

    -- 1. Ingest runs not yet processed (all of bronze on a first build)
    new_runs AS (
        {{ new_ingest_runs(ref('eia_fuel_type_data__base')) }}
    )

-- 2. Newest version per hour × fuel (several runs may arrive at once)
SELECT
    hour_start_at,
    fuel,
    fuel_name,
    generation_mwh,
    ingested_at,
    ingested_by
FROM new_runs
{{ keep_latest_version(['hour_start_at', 'fuel']) }}
