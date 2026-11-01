{#
  silver.eia_region_data__base — one row per hour × measure × ingest run

  Every EIA-930 hourly value for ISO New England (decision 0014): demand, ISO-NE's
  day-ahead demand forecast, net generation and interchange. Two bronze tables,
  one shape: the API's (eia_region_data, 2019 on) and the bulk files' reshaped
  to match (eia_region_data_bulk, 2015-07 to 2018-12). They cover different
  years, so no hour comes from both.

  EIA labels each hour by its end; this model labels it by its start, like
  every other source here, so 06:00 UTC "hour ending" becomes hour_start_at
  05:00 UTC.

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as eia_region_data__latest does): the filter reaches both bronze tables'
  partitions through the view. No tests here: they would scan all of bronze
  (decision 0003).

  Steps:
    1. both_sources — the API and bulk tables, with which one each row is from
    2. final select — hour end → hour start; rename to project conventions
#}

WITH

    -- 1. The API (2019 on) and the bulk files (2015–2018), in one shape
    both_sources AS (
        SELECT
            *,
            'api' AS source
        FROM {{ source('bronze', 'eia_region_data') }}
        UNION ALL
        SELECT
            *,
            'bulk' AS source
        FROM {{ source('bronze', 'eia_region_data_bulk') }}
    )

-- 2. Hour start, project names
SELECT
    TIMESTAMP_SUB(period, INTERVAL 1 HOUR)  AS hour_start_at,
    type                                    AS measure,
    type_name                               AS measure_name,
    value                                   AS value_mwh,
    source,
    ingested_at,
    ingested_by
FROM both_sources
WHERE respondent = 'ISNE'
