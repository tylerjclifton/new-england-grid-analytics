{#
  silver.isone_rt_lmp__hourly — one row per hour × location

  ISO-NE's real-time price for each hour at the Hub and each load zone, from
  2019 on, from whichever feed has the hour (decisions 0012, 0013):
    five_minute  2024 on: the mean of the hour's five-minute prices
                 (isone_rt_lmp__latest), which is how ISO-NE computes its
                 hourly price, plus the hour's highest five-minute price
    hourly       before that: ISO-NE's hourly price (isone_rt_lmp_hourly__latest);
                 no five-minute peak
  Where both have an hour (2024), five-minute wins: it's the same price and
  also has the peak.

  A view over silver tables, read by gold (grid_hourly, grid_zone_hourly).

  Steps:
    1. five_minute  — five-minute prices rolled up to the hour
    2. final select — five-minute hours, then hourly-feed hours not covered
#}

WITH

    -- 1. Five-minute prices rolled up to the hour
    five_minute AS (
        SELECT
            TIMESTAMP_TRUNC(interval_start_at, HOUR)  AS hour_start_at,
            location_code,
            AVG(lmp_usd_mwh)                          AS lmp_usd_mwh,
            AVG(energy_usd_mwh)                       AS energy_usd_mwh,
            AVG(congestion_usd_mwh)                   AS congestion_usd_mwh,
            AVG(loss_usd_mwh)                         AS loss_usd_mwh,
            MAX(lmp_usd_mwh)                          AS lmp_max_five_minute_usd_mwh,
            LOGICAL_AND(is_final)                     AS is_final,
            COUNT(*)                                  AS intervals
        FROM {{ ref('isone_rt_lmp__latest') }}
        GROUP BY hour_start_at, location_code
    )

-- 2. Five-minute hours, then the hourly backfill's hours not covered by them
SELECT
    hour_start_at,
    location_code,
    lmp_usd_mwh,
    energy_usd_mwh,
    congestion_usd_mwh,
    loss_usd_mwh,
    lmp_max_five_minute_usd_mwh,
    is_final,
    intervals,
    'five_minute' AS price_source
FROM five_minute
UNION ALL
SELECT
    hourly.hour_start_at,
    hourly.location_code,
    hourly.lmp_usd_mwh,
    hourly.energy_usd_mwh,
    hourly.congestion_usd_mwh,
    hourly.loss_usd_mwh,
    CAST(NULL AS FLOAT64) AS lmp_max_five_minute_usd_mwh,
    TRUE                  AS is_final,
    CAST(NULL AS INT64)   AS intervals,
    'hourly'              AS price_source
FROM {{ ref('isone_rt_lmp_hourly__latest') }} AS hourly
LEFT JOIN five_minute
    ON hourly.hour_start_at = five_minute.hour_start_at
    AND hourly.location_code = five_minute.location_code
WHERE five_minute.hour_start_at IS NULL
