{#
  silver.isone_rt_lmp_hourly__latest — one row per hour × location

  The final hourly real-time price for each hour of 2019–2024 at the Hub and
  each load zone (decision 0013). From 2024 on, hourly real-time prices are
  derived from the five-minute feed (isone_rt_lmp__latest) instead; the
  months in both check that derivation.

  Incremental: each run reads only ingest runs added since the last one (the
  ingested_at literal prunes bronze's partitions through the __base view) and
  merges them in on hour × location. It's a one-off backfill, so the table
  holds ~480,000 rows and grows only if the backfill is re-run.
  `dbt build --full-refresh` rebuilds it from all of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per hour × location among them (merged in
                         on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['hour_start_at', 'location_code'],
        incremental_strategy='merge',
        cluster_by=['location_code', 'hour_start_at'],
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
        FROM {{ ref('isone_rt_lmp_hourly__base') }}
        {%- if processed_through %}
        WHERE ingested_at > TIMESTAMP '{{ processed_through }}'
        {%- endif %}
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
