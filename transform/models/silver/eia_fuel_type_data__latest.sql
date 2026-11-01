{#
  silver.eia_fuel_type_data__latest — one row per hour × fuel

  The newest value EIA has given for each hour's generation from each fuel in
  ISO New England (see eia_fuel_type_data__base).

  Incremental: each run reads only ingest runs added since the last one (the
  ingested_at literal prunes bronze's partitions through the __base view) and
  merges them in on hour × fuel. The table grows ~95,000 rows a year.
  `dbt build --full-refresh` rebuilds it from all of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per hour × fuel among them (merged in on
                         that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['hour_start_at', 'fuel'],
        incremental_strategy='merge',
        cluster_by=['fuel', 'hour_start_at'],
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
        FROM {{ ref('eia_fuel_type_data__base') }}
        {%- if processed_through %}
        WHERE ingested_at > TIMESTAMP '{{ processed_through }}'
        {%- endif %}
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
