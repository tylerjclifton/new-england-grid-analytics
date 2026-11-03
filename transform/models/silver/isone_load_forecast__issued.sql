{#
  silver.isone_load_forecast__issued — one row per hour × version

  Each version ISO-NE issued of its system load forecast, once (see
  isone_load_forecast__base). Runs re-pull overlapping days, so a version
  arrives several times; this keeps the newest copy of each.
  isone_load_forecast__day_ahead picks the benchmark version from it
  (decision 0017).

  Incremental: each run reads only ingest runs added since the last one
  (macros/new_ingest_runs.sql) and merges them in on hour × version. The
  table grows ~90,000 rows a year (about 10 versions an hour).
  `dbt build --full-refresh` rebuilds it from all of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest copy per hour × version among them (merged in
                         on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['hour_start_at', 'issued_at'],
        cluster_by=['hour_start_at'],
        partition_by=monthly_partitions('hour_start_at'),
        incremental_predicates=recent_merge_window('hour_start_at')
    )
}}

WITH

    -- 1. Ingest runs not yet processed (all of bronze on a first build)
    new_runs AS (
        {{ new_ingest_runs(ref('isone_load_forecast__base')) }}
    )

-- 2. Newest copy per hour × version
SELECT
    hour_start_at,
    issued_at,
    lead_hours,
    load_mw,
    net_load_mw,
    ingested_at,
    ingested_by
FROM new_runs
{{ keep_latest_version(['hour_start_at', 'issued_at']) }}
