{#
  silver.openmeteo_previous_runs__latest — one row per load zone × hour × lead

  What was forecast for each hour 1 and 2 days before it, at each load zone's
  point, 2021 to 2026-10-28 (see openmeteo_previous_runs__base): the weather a
  day-ahead model may train on.

  Incremental: each run reads only ingest runs added since the last one (the
  ingested_at literal prunes bronze's partitions through the __base view) and
  merges them in on load zone × hour × lead. It's a one-off backfill, so the
  table holds ~820,000 rows and grows only if the backfill is re-run.
  `dbt build --full-refresh` rebuilds it from all of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per load zone × hour × lead among them
                         (merged in on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['load_zone', 'hour_at', 'lead_days'],
        incremental_strategy='merge',
        cluster_by=['load_zone', 'hour_at'],
        on_schema_change='append_new_columns'
    )
}}

{#- The newest ingest run already processed (none on a first build), compiled
    in as a literal so bronze's partitions are pruned -#}
{%- set processed_through = last_processed_run() %}

WITH

    -- 1. Ingest runs not yet processed (all of bronze on the first run)
    new_runs AS (
        SELECT *
        FROM {{ ref('openmeteo_previous_runs__base') }}
        {%- if processed_through %}
        WHERE ingested_at > TIMESTAMP '{{ processed_through }}'
        {%- endif %}
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
