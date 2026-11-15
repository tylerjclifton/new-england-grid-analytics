{#
  silver.eia_natural_gas_prices__latest — one row per series × period

  EIA's newest figure for each natural gas price (see
  eia_natural_gas_prices__base). Each daily run re-pulls a month of Henry Hub
  and two years of the state prices, which EIA revises (decision 0019).

  Incremental: each run reads only ingest runs added since the last one
  (macros/new_ingest_runs.sql) and merges them in on series × period. Unlike
  the other incremental models, the merge looks at the whole table, not the
  last 35 days (recent_merge_window): revisions reach back two years, and the
  table stays tiny (~4,000 rows, ~350 more a year), so a full merge costs
  nothing. Unpartitioned for the same reason.

  Steps:
    1. new_runs     — rows ingested after the newest one already here
    2. final select — newest row per series × period among them (merged in
                      on that key)
#}

{{
    config(
        materialized='incremental',
        unique_key=['series', 'price_date'],
        cluster_by=['series', 'price_date']
    )
}}

WITH

    -- 1. Ingest runs not yet processed (all of bronze on a first build)
    new_runs AS (
        {{ new_ingest_runs(ref('eia_natural_gas_prices__base')) }}
    )

-- 2. Newest version per series × period (several runs may arrive at once)
SELECT
    price_date,
    frequency,
    series,
    series_name,
    state,
    price_usd_mmbtu,
    price_usd_mcf,
    units,
    ingested_at,
    ingested_by
FROM new_runs
{{ keep_latest_version(['series', 'price_date']) }}
