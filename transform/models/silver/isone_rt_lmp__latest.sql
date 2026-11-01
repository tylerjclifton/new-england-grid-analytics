{#
  silver.isone_rt_lmp__latest — one row per five-minute interval × location

  The best real-time price for each interval at the Hub and each load zone:
  the final price once ISO-NE has published it, the newest preliminary one
  until then (decision 0012). is_final says which.

  Incremental: each run reads only ingest runs added since the last one (the
  ingested_at literal prunes bronze's partitions through the __base view) and
  merges them in on interval × location, so a final price replaces the
  preliminary one when it arrives. A preliminary price can't overwrite a final
  one: the ingest pulls them for different days (yesterday and today vs. 2–3
  days ago), and within a batch the final one wins. The table grows ~950,000
  rows a year. `dbt build --full-refresh` rebuilds it from all of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — per interval × location among them: final over
                         preliminary, then the newest (merged in on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['interval_start_at', 'location_code'],
        incremental_strategy='merge',
        cluster_by=['location_code', 'interval_start_at'],
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
        FROM {{ ref('isone_rt_lmp__base') }}
        {%- if processed_through %}
        WHERE ingested_at > TIMESTAMP '{{ processed_through }}'
        {%- endif %}
    )

-- 2. Best version per interval × location: final first, then the newest run
SELECT
    interval_start_at,
    location_code,
    location_id,
    lmp_usd_mwh,
    energy_usd_mwh,
    congestion_usd_mwh,
    loss_usd_mwh,
    is_final,
    ingested_at,
    ingested_by
FROM new_runs
{{ keep_latest_version(['interval_start_at', 'location_code'], prefer='is_final DESC') }}
