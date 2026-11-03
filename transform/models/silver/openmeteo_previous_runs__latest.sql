{#
  silver.openmeteo_previous_runs__latest — one row per load zone × hour × lead

  What was forecast for each hour 1 and 2 days before it, at each load zone's
  point, 2021 to 2026-10-28 (see openmeteo_previous_runs__base): the weather a
  day-ahead model may train on.

  Incremental: each run reads only ingest runs added since the last one
  (macros/new_ingest_runs.sql) and merges them in on load zone × hour × lead.
  It's a one-off backfill, so the table holds ~820,000 rows and grows only if
  the backfill is re-run. `dbt build --full-refresh` rebuilds it from all of
  bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per load zone × hour × lead among them
                         (merged in on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['load_zone', 'hour_at', 'lead_days'],
        cluster_by=['load_zone', 'hour_at'],
        partition_by=monthly_partitions('hour_at'),
        incremental_predicates=recent_merge_window('hour_at')
    )
}}

WITH

    -- 1. Ingest runs not yet processed (all of bronze on a first build)
    new_runs AS (
        {{ new_ingest_runs(ref('openmeteo_previous_runs__base')) }}
    )

-- 2. Newest value per load zone × hour × lead
SELECT
    load_zone,
    location_name,
    hour_at,
    lead_days,
    temperature_f,
    dew_point_f,
    cloud_cover_pct,
    solar_irradiance_w_m2,
    wind_speed_10m_ms,
    wind_speed_100m_ms,
    precipitation_mm,
    snowfall_cm,
    latitude,
    longitude,
    ingested_at,
    ingested_by
FROM new_runs
{{ keep_latest_version(['load_zone', 'hour_at', 'lead_days']) }}
