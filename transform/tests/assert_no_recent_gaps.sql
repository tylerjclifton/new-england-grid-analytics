{#
  Every core source covers every hour of the recent past: from 10 days ago to
  3 days ago (by then EIA's revisions and ISO-NE's final prices are in). A
  source that stops entirely trips the freshness check; this catches one that
  keeps running but loses hours (a day file that comes back short, a feed
  that drops a day). Historically, gaps are rare and scattered
  (docs/data-quality.md): 8 hours of EIA demand since 2015, 96 of fuel mix
  since 2019, none of prices.

  Fails (warns) with each source × hour missing. Warn, not error: an upstream
  gap isn't fixed by blocking the build, and old gaps stay as they are.
#}

{{ config(severity='warn') }}

WITH

    recent AS (
        SELECT *
        FROM {{ ref('grid_hourly') }}
        WHERE hour_start_at >= TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR), INTERVAL 10 DAY)
          AND hour_start_at < TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR), INTERVAL 3 DAY)
    )

-- One row per hour × source checked, kept where the source has nothing
SELECT
    recent.hour_start_at,
    checks.source
FROM recent
CROSS JOIN UNNEST([
    STRUCT('EIA demand' AS source, recent.eia_demand_mwh IS NULL AS is_missing),
    STRUCT('system load' AS source, recent.load_mw IS NULL AS is_missing),
    STRUCT('fuel mix' AS source, recent.natural_gas_mw IS NULL AS is_missing),
    STRUCT('Hub real-time price' AS source, recent.rt_lmp_usd_mwh IS NULL AS is_missing),
    STRUCT('Hub day-ahead price' AS source, recent.da_lmp_usd_mwh IS NULL AS is_missing),
    STRUCT('ISO-NE load forecast' AS source, recent.isone_load_forecast_mw IS NULL AS is_missing)
]) AS checks
WHERE checks.is_missing
