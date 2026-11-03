{#
  silver.isone_wind_forecast__issued — one row per hour × publication

  Each publication's wind forecast for each hour, once (see
  isone_wind_forecast__base). Runs re-pull overlapping days, so a
  publication arrives several times; this keeps the newest copy of each.
  isone_wind_forecast__day_ahead picks the benchmark publication from it
  (decision 0017).

  Incremental: each run reads only ingest runs added since the last one
  (macros/new_ingest_runs.sql) and merges them in on hour × publication. The
  table grows ~60,000 rows a year (about 7 publications an hour).
  `dbt build --full-refresh` rebuilds it from all of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest copy per hour × publication among them
                         (merged in on that key)
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
        {{ new_ingest_runs(ref('isone_wind_forecast__base')) }}
    )

-- 2. Newest copy per hour × publication
SELECT
    hour_start_at,
    issued_at,
    lead_hours,
    wind_mw,
    market_date,
    hour_ending,
    ingested_at,
    ingested_by
FROM new_runs
{{ keep_latest_version(['hour_start_at', 'issued_at']) }}
