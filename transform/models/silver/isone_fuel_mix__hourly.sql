{#
  silver.isone_fuel_mix__hourly — one row per hour

  ISO-NE's fuel mix (isone_fuel_mix__latest) as hourly MW per fuel, one column
  each, and the fuel most often setting the price during the hour.

  Snapshots arrive at irregular times (~8 an hour), each listing only the fuels
  running, so a fuel's hourly MW is the mean over the hour's snapshots with an
  absent fuel counted as 0. (A snapshot is a moment, not an interval; the mean
  of moments is close to the hour's average, not exact.)

  A view over a silver table, read by gold (grid_hourly).

  Steps:
    1. by_hour     — each snapshot × fuel with its hour
    2. snapshots   — how many snapshots each hour had
    3. marginal    — the fuel marginal in the most snapshots of each hour
    4. final select — one column per fuel: MW summed over the hour's
                      snapshots ÷ the hour's snapshot count (absent = 0)
#}

{#- ISO-NE fuel categories (FuelCategory) → column names; seen 2019–2026 -#}
{%- set fuels = [
    ('Natural Gas', 'natural_gas'), ('Nuclear', 'nuclear'), ('Hydro', 'hydro'),
    ('Wind', 'wind'), ('Solar', 'solar'), ('Oil', 'oil'), ('Coal', 'coal'),
    ('Wood', 'wood'), ('Refuse', 'refuse'), ('Landfill Gas', 'landfill_gas'),
    ('Batteries', 'batteries'), ('Other', 'other'),
] %}

WITH

    -- 1. Each snapshot × fuel, with the hour it falls in
    by_hour AS (
        SELECT
            TIMESTAMP_TRUNC(snapshot_at, HOUR) AS hour_start_at,
            snapshot_at,
            fuel,
            generation_mw,
            is_marginal
        FROM {{ ref('isone_fuel_mix__latest') }}
    ),

    -- 2. Snapshots per hour: the denominator, so an absent fuel counts as 0
    snapshots AS (
        SELECT
            hour_start_at,
            COUNT(DISTINCT snapshot_at) AS snapshot_count
        FROM by_hour
        GROUP BY hour_start_at
    ),

    -- 3. The fuel marginal in the most of the hour's snapshots (ties: alphabetical)
    marginal AS (
        SELECT
            hour_start_at,
            ARRAY_AGG(fuel ORDER BY marginal_snapshots DESC, fuel ASC LIMIT 1)[OFFSET(0)] AS marginal_fuel
        FROM (
            SELECT
                hour_start_at,
                fuel,
                COUNT(*) AS marginal_snapshots
            FROM by_hour
            WHERE is_marginal
            GROUP BY hour_start_at, fuel
        ) AS marginal_counts
        GROUP BY hour_start_at
    )

-- 4. One column per fuel, MW averaged over the hour's snapshots
SELECT
    by_hour.hour_start_at,
    {%- for category, column in fuels %}
    SUM(IF(by_hour.fuel = '{{ category }}', by_hour.generation_mw, 0)) / ANY_VALUE(snapshots.snapshot_count)
        AS {{ column }}_mw,
    {%- endfor %}
    SUM(by_hour.generation_mw) / ANY_VALUE(snapshots.snapshot_count) AS total_generation_mw,
    ANY_VALUE(marginal.marginal_fuel)                                  AS marginal_fuel,
    ANY_VALUE(snapshots.snapshot_count)                                AS snapshot_count
FROM by_hour
INNER JOIN snapshots ON by_hour.hour_start_at = snapshots.hour_start_at
LEFT JOIN marginal ON by_hour.hour_start_at = marginal.hour_start_at
GROUP BY by_hour.hour_start_at
