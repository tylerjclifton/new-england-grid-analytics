{#
  silver.eia_fuel_type_data__base — one row per hour × fuel × ingest run

  Every EIA-930 hourly net generation value by fuel for ISO New England
  (decision 0014), 2019 on. A fuel EIA doesn't report for an hour is null or
  absent, not 0 (coal and oil, most of the year).

  EIA labels each hour by its end; this model labels it by its start, like
  every other source here.

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as eia_fuel_type_data__latest does). No tests here: they would scan all of
  bronze (decision 0003).

  Steps:
    1. final select — hour end → hour start; rename to project conventions
#}

SELECT
    TIMESTAMP_SUB(period, INTERVAL 1 HOUR)  AS hour_start_at,
    fueltype                                AS fuel,
    type_name                               AS fuel_name,
    value                                   AS generation_mwh,
    ingested_at,
    ingested_by
FROM {{ source('bronze', 'eia_fuel_type_data') }}
WHERE respondent = 'ISNE'
