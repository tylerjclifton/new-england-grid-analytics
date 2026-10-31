{#
  silver.isone_system_load__latest — one row per five-minute interval

  The newest version ISO-NE has published of each interval's load, with and
  without rooftop solar (see isone_system_load__base).

  Incremental: each run reads only ingest runs added since the last one (the
  ingested_at literal prunes bronze's partitions through the __base view) and
  merges them in, replacing older versions of the same interval. The table
  grows ~105,000 rows a year. `dbt build --full-refresh` rebuilds it from all
  of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per interval among them (merged in on that
                         key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['interval_start_at'],
        incremental_strategy='merge',
        cluster_by=['interval_start_at'],
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
        FROM {{ ref('isone_system_load__base') }}
        {%- if processed_through %}
        WHERE ingested_at > TIMESTAMP '{{ processed_through }}'
        {%- endif %}
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
