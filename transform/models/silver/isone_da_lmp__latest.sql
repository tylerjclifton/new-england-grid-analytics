{#
  silver.isone_da_lmp__latest — one row per hour × location

  The day-ahead price for each hour at the Hub and each load zone: what the
  market expected the real-time price to be, set around midday the day before
  (decision 0012).

  Incremental: each run reads only ingest runs added since the last one (the
  ingested_at literal prunes bronze's partitions through the __base view) and
  merges them in on hour × location. The table grows ~79,000 rows a year.
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
        FROM {{ ref('isone_da_lmp__base') }}
        {%- if processed_through %}
        WHERE ingested_at > TIMESTAMP '{{ processed_through }}'
        {%- endif %}
    )

-- 2. Newest version per hour × location (several runs may arrive at once)
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
