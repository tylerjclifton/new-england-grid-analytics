{#
  silver.openmeteo_archive__latest — one row per load zone × hour

  The newest reanalysis value for each hour at each load zone's point, from
  2015-07: the weather as it was (see openmeteo_archive__base).

  Incremental: each run reads only ingest runs added since the last one (the
  ingested_at literal prunes bronze's partitions through the __base view) and
  merges them in on load zone × hour. The table grows ~70,000 rows a year
  (~800,000 back to 2015). `dbt build --full-refresh` rebuilds it from all of
  bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per load zone × hour among them (merged
                         in on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['load_zone', 'hour_at'],
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
        FROM {{ ref('openmeteo_archive__base') }}
        {%- if processed_through %}
        WHERE ingested_at > TIMESTAMP '{{ processed_through }}'
        {%- endif %}
    )

-- 2. Newest value per load zone × hour
SELECT
    load_zone,
    location_name,
    hour_at,
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
{{ keep_latest_version(['load_zone', 'hour_at']) }}
