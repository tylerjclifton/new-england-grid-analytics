{#
  silver.isone_zonal_load_forecast__day_ahead — one row per hour × load zone

  ISO-NE's forecast as it stood at the day-ahead deadline: for each hour × load zone,
  the last version issued by 10:00 Eastern the day before
  (macros/day_ahead_deadline.sql, decision 0017). This is the benchmark a
  day-ahead model competes with: what ISO-NE had at the same moment.

  A view over isone_zonal_load_forecast__issued (a table), read by gold.

  Steps:
    1. final select — versions issued by the deadline; the latest of them per
                      hour × load zone
#}

SELECT
    hour_start_at,
    load_zone,
    issued_at,
    lead_hours,
    load_mw,
    share_of_system_pct
FROM {{ ref('isone_zonal_load_forecast__issued') }}
WHERE issued_at <= {{ day_ahead_deadline('hour_start_at') }}
QUALIFY ROW_NUMBER() OVER (PARTITION BY hour_start_at, load_zone ORDER BY issued_at DESC) = 1
