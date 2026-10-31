{#
  silver.isone_fuel_mix__latest — one row per snapshot × fuel

  The newest version ISO-NE has published of each snapshot: what was running,
  how much, and which fuel was marginal. Fuels not running are absent (see
  isone_fuel_mix__base).

  Incremental: each run reads only ingest runs added since the last one (the
  ingested_at literal prunes bronze's partitions through the __base view) and
  merges them in, replacing older versions of the same snapshot × fuel. The
  table grows ~700,000 rows a year. `dbt build --full-refresh` rebuilds it
  from all of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — newest row per snapshot × fuel among them (merged in
                         on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['snapshot_at', 'fuel'],
        incremental_strategy='merge',
        cluster_by=['fuel', 'snapshot_at'],
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
        FROM {{ ref('isone_fuel_mix__base') }}
        {%- if processed_through %}
        WHERE ingested_at > TIMESTAMP '{{ processed_through }}'
        {%- endif %}
    )

-- 2. Newest version per snapshot × fuel (several runs may arrive at once)
SELECT
    snapshot_at,
    fuel,
    fuel_group,
    generation_mw,
    is_marginal,
    ingested_at,
    ingested_by
FROM new_runs
{{ keep_latest_version(['snapshot_at', 'fuel']) }}
