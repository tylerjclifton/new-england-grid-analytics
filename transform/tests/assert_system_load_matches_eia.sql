{#
  ISO-NE's system load and EIA-930's demand are the same quantity: EIA's
  figure for ISO New England is ISO-NE's system load, by the hour. On
  2026-11-02 they agreed to within 1% in all but 4 of 21,143 hours
  (docs/data-quality.md lists those), which also shows the hour-end →
  hour-start shift for EIA is right. A new disagreement over 1% means one
  source changed, or an hour label slipped.

  Checks the last 10 days only, so it warns about new data, not the known
  historical exceptions every run. Fails (warns) with each hour that
  disagrees. Warn, not error: it's a cross-check between sources, not a fault
  in either one to block on.
#}

{{ config(severity='warn') }}

SELECT
    hour_start_at,
    load_mw,
    eia_demand_mwh,
    ROUND((load_mw - eia_demand_mwh) / eia_demand_mwh * 100, 2) AS pct_difference
FROM {{ ref('grid_hourly') }}
WHERE load_mw IS NOT NULL
  AND eia_demand_mwh > 0
  AND ABS(load_mw - eia_demand_mwh) / eia_demand_mwh > 0.01
  AND hour_start_at >= TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR), INTERVAL 10 DAY)
