{#
  silver.eia_natural_gas_prices__daily — one row per Eastern date × series

  The natural gas price in effect on each date, for gold to join by date
  (decision 0019):
    - Henry Hub: the latest trading day's price on or before the date, at
      most 4 days back (a weekend and a holiday), so a stalled feed shows as
      null rather than as an old price that looks current;
    - each state's power plant price: its month's.
  price_date says which trading day or month the price is from. A date with
  no price in effect (a month EIA hasn't published yet, a state it withholds)
  has no row for that series.

  The calendar runs from the first price to 4 days past the latest month's
  end: as far as any price can carry, and fixed by the data rather than by
  today, so the unit test's output doesn't change from day to day.

  A view over a tiny table (eia_natural_gas_prices__latest), read by gold.

  Steps:
    1. calendar      — every date a price can be in effect on
    2. daily_series  — the series priced by trading day (Henry Hub)
    3. daily_prices  — each of them on every date, with that day's trade if any
    4. carried       — the latest trade within the last 4 days
    5. final select  — daily series as carried, monthly series by month
#}

WITH

    -- 1. Every date from the first price to 4 days past the latest month's end
    calendar AS (
        SELECT local_date
        FROM UNNEST(GENERATE_DATE_ARRAY(
            (SELECT MIN(price_date) FROM {{ ref('eia_natural_gas_prices__latest') }}),
            (
                SELECT DATE_ADD(LAST_DAY(MAX(price_date)), INTERVAL 4 DAY)
                FROM {{ ref('eia_natural_gas_prices__latest') }}
            )
        )) AS local_date
    ),

    -- 2. The series priced each trading day
    daily_series AS (
        SELECT DISTINCT series
        FROM {{ ref('eia_natural_gas_prices__latest') }}
        WHERE frequency = 'daily'
    ),

    -- 3. Each daily series on every date: that day's trade, or nulls
    daily_prices AS (
        SELECT
            calendar.local_date,
            daily_series.series,
            prices.price_date,
            prices.price_usd_mmbtu
        FROM calendar
        CROSS JOIN daily_series
        LEFT JOIN {{ ref('eia_natural_gas_prices__latest') }} AS prices
            ON daily_series.series = prices.series
            AND calendar.local_date = prices.price_date
            AND prices.price_usd_mmbtu IS NOT NULL
    ),

    -- 4. The latest trade on or before each date, at most 4 days back (one
    --    row per date, so 4 preceding rows are 4 days)
    carried AS (
        SELECT
            local_date,
            series,
            LAST_VALUE(price_date IGNORE NULLS) OVER recent_days       AS price_date,
            LAST_VALUE(price_usd_mmbtu IGNORE NULLS) OVER recent_days  AS price_usd_mmbtu
        FROM daily_prices
        WINDOW recent_days AS (PARTITION BY series ORDER BY local_date ROWS BETWEEN 4 PRECEDING AND CURRENT ROW)
    )

-- 5. Daily series as carried; monthly series for every date in their month
SELECT
    local_date,
    series,
    'daily'                  AS frequency,
    CAST(NULL AS STRING)     AS state,
    price_date,
    price_usd_mmbtu,
    CAST(NULL AS FLOAT64)    AS price_usd_mcf
FROM carried
WHERE price_date IS NOT NULL

UNION ALL

SELECT
    calendar.local_date,
    prices.series,
    prices.frequency,
    prices.state,
    prices.price_date,
    prices.price_usd_mmbtu,
    prices.price_usd_mcf
FROM calendar
INNER JOIN {{ ref('eia_natural_gas_prices__latest') }} AS prices
    ON DATE_TRUNC(calendar.local_date, MONTH) = prices.price_date
    AND prices.frequency = 'monthly'
WHERE prices.price_usd_mcf IS NOT NULL
