{#
  silver.eia_natural_gas_prices__base — one row per series × period × ingest run

  Every EIA natural gas price this project pulls (decision 0019): the Henry
  Hub spot price each trading day, $/MMBtu, and the monthly price New England
  power plants paid for gas in each state, $/MCF (null where EIA withholds it).
  A monthly price's date is the month's first day.

  The two units are kept apart, each in its own column: converting MCF to
  MMBtu needs the gas's heat content, which varies by state and year.

  A view, so it costs nothing until read. Read it with an ingested_at filter
  (as eia_natural_gas_prices__latest does). No tests here: they would scan
  all of bronze (decision 0003).

  Steps:
    1. final select — rename to project conventions; the state from EIA's
                      area code (SMA → MA; none for Henry Hub); the price in
                      the column for its unit
#}

SELECT
    period                                                     AS price_date,
    frequency,
    series,
    series_description                                         AS series_name,
    IF(STARTS_WITH(duoarea, 'S'), SUBSTR(duoarea, 2), NULL)    AS state,
    IF(units = '$/MMBTU', value, NULL)                         AS price_usd_mmbtu,
    IF(units = '$/MCF', value, NULL)                           AS price_usd_mcf,
    units,
    ingested_at,
    ingested_by
FROM {{ source('bronze', 'eia_natural_gas_prices') }}
