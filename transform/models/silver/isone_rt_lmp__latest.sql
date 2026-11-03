{#
  silver.isone_rt_lmp__latest — one row per five-minute interval × location

  The best real-time price for each interval at the Hub and each load zone:
  the final price once ISO-NE has published it, the newest preliminary one
  until then (decision 0012). is_final says which.

  Incremental: each run reads only ingest runs added since the last one
  (macros/new_ingest_runs.sql) and merges them in on interval × location, so a
  final price replaces the preliminary one when it arrives. A preliminary price
  can't overwrite a final one: the ingest pulls them for different days
  (yesterday and today vs. 2–3 days ago), and within a batch the final one
  wins. The table grows ~950,000 rows a year. `dbt build --full-refresh`
  rebuilds it from all of bronze.

  Steps:
    1. new_runs        — rows ingested after the newest one already here
    2. final select    — per interval × location among them: final over
                         preliminary, then the newest (merged in on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['interval_start_at', 'location_code'],
        cluster_by=['location_code', 'interval_start_at'],
        partition_by=monthly_partitions('interval_start_at'),
        incremental_predicates=recent_merge_window('interval_start_at')
    )
}}

WITH

    -- 1. Ingest runs not yet processed (all of bronze on a first build)
    new_runs AS (
        {{ new_ingest_runs(ref('isone_rt_lmp__base')) }}
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
{{ keep_latest_version(
    ['interval_start_at', 'location_code'],
    prefer='is_final DESC'
) }}
