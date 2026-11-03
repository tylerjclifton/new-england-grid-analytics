{#
  silver.isone_wind_forecast__day_ahead — one row per hour

  ISO-NE's forecast as it stood at the day-ahead deadline: for each hour,
  the last version issued by 10:00 Eastern the day before
  (macros/day_ahead_deadline.sql, decision 0017). This is the benchmark a
  day-ahead model competes with: what ISO-NE had at the same moment.
  ISO-NE publishes it about 8:30 Eastern, so this is the morning publication
  of the day before.

  A view over isone_wind_forecast__issued (a table), read by gold.

  Steps:
    1. final select — versions issued by the deadline; the latest of them per
                      hour
#}

SELECT
    hour_start_at,
    issued_at,
    lead_hours,
    wind_mw
FROM {{ ref('isone_wind_forecast__issued') }}
WHERE issued_at <= {{ day_ahead_deadline('hour_start_at') }}
QUALIFY ROW_NUMBER() OVER (PARTITION BY hour_start_at ORDER BY issued_at DESC) = 1
