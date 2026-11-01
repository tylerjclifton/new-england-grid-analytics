{#
  silver.eia_region_data__by_hour — one row per hour

  ISO New England's hour from EIA-930, one measure per column: demand, ISO-NE's
  own day-ahead forecast of it, net generation, and interchange (net exports;
  negative means New England imported). The forecast beside the actual is the
  benchmark a load model has to beat, back to 2015-07.

  A view over eia_region_data__latest (a small table, ~100,000 hours), so it
  needs no refresh of its own.

  Steps:
    1. final select — one column per measure (a measure missing for an hour
                      is null)
#}

SELECT
    hour_start_at,
    MAX(IF(measure = 'D',  value_mwh, NULL))  AS demand_mwh,
    MAX(IF(measure = 'DF', value_mwh, NULL))  AS demand_forecast_mwh,
    MAX(IF(measure = 'NG', value_mwh, NULL))  AS net_generation_mwh,
    MAX(IF(measure = 'TI', value_mwh, NULL))  AS interchange_mwh,
    ANY_VALUE(source)                         AS source,
    MAX(ingested_at)                          AS ingested_at
FROM {{ ref('eia_region_data__latest') }}
GROUP BY hour_start_at
