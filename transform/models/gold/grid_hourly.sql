{#
  gold.grid_hourly — one row per hour, New England as a whole

  Every hour from 2015-07-01 (Eastern midnight) through the latest hour any
  source has (tomorrow, once day-ahead prices are out), with what each source
  says about it. A source that doesn't cover an hour leaves its columns null;
  coverage starts at:
    2015-07  EIA demand and ISO-NE's day-ahead demand forecast
    2019-01  EIA net generation and interchange (from 2015 too), Hub
             real-time and day-ahead prices (from mid-2019)
    2019-06  fuel mix and the marginal fuel
    2024     system load with ISO-NE's rooftop solar estimate; five-minute
             price peaks

  The input to the dashboard and to models of load and price. A table,
  rebuilt every transform run from silver (~100,000 rows).

  Steps:
    1. hours        — every hour in range (a spine, so missing data shows as null)
    2. hub_prices   — the Hub's real-time and day-ahead prices
    3. final select — the spine with every source joined on hour; Eastern
                      calendar columns
#}

WITH

    -- 1. Every hour from 2015-07-01 00:00 Eastern to the latest hour any source has
    hours AS (
        SELECT hour_start_at
        FROM UNNEST(GENERATE_TIMESTAMP_ARRAY(
            TIMESTAMP '2015-07-01 04:00:00+00',
            GREATEST(
                TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR),
                (SELECT MAX(hour_start_at) FROM {{ ref('isone_da_lmp__latest') }})
            ),
            INTERVAL 1 HOUR
        )) AS hour_start_at
    ),

    -- 2. The Hub's prices: real time (from 2019) and day ahead
    hub_prices AS (
        SELECT
            hours.hour_start_at,
            rt.lmp_usd_mwh                  AS rt_lmp_usd_mwh,
            rt.lmp_max_five_minute_usd_mwh  AS rt_lmp_max_five_minute_usd_mwh,
            rt.is_final                     AS rt_is_final,
            da.lmp_usd_mwh                  AS da_lmp_usd_mwh
        FROM hours
        LEFT JOIN {{ ref('isone_rt_lmp__hourly') }} AS rt
            ON hours.hour_start_at = rt.hour_start_at AND rt.location_code = 'HUB'
        LEFT JOIN {{ ref('isone_da_lmp__latest') }} AS da
            ON hours.hour_start_at = da.hour_start_at AND da.location_code = 'HUB'
    )

-- 3. One row per hour, every source side by side
SELECT
    hours.hour_start_at,
    {{ eastern_calendar_columns('hours.hour_start_at') }},
    holidays.holiday_name,
    COALESCE(holidays.is_nerc_holiday, FALSE)      AS is_nerc_holiday,
    COALESCE(holidays.is_federal_holiday, FALSE)   AS is_federal_holiday,

    -- Demand (EIA-930, from 2015-07): actual and ISO-NE's own day-ahead forecast
    eia.demand_mwh                          AS eia_demand_mwh,
    eia.demand_forecast_mwh                 AS eia_demand_forecast_mwh,
    eia.net_generation_mwh                  AS eia_net_generation_mwh,
    eia.interchange_mwh                     AS eia_interchange_mwh,

    -- System load (ISO-NE, from 2024): measured, and with rooftop solar added back
    system_load.load_mw,
    system_load.btm_solar_mw,
    system_load.load_with_btm_solar_mw,

    -- Generation by fuel (ISO-NE, from 2019-06), MW, absent fuels as 0
    fuel_mix.natural_gas_mw,
    fuel_mix.nuclear_mw,
    fuel_mix.hydro_mw,
    fuel_mix.wind_mw,
    fuel_mix.solar_mw,
    fuel_mix.oil_mw,
    fuel_mix.coal_mw,
    fuel_mix.wood_mw,
    fuel_mix.refuse_mw,
    fuel_mix.landfill_gas_mw,
    fuel_mix.batteries_mw,
    fuel_mix.other_mw,
    fuel_mix.total_generation_mw,
    fuel_mix.marginal_fuel,

    -- The Hub's prices, $/MWh
    hub_prices.rt_lmp_usd_mwh,
    hub_prices.rt_lmp_max_five_minute_usd_mwh,
    hub_prices.rt_is_final,
    hub_prices.da_lmp_usd_mwh
FROM hours
LEFT JOIN {{ ref('eia_region_data__by_hour') }} AS eia ON hours.hour_start_at = eia.hour_start_at
LEFT JOIN {{ ref('isone_system_load__hourly') }} AS system_load ON hours.hour_start_at = system_load.hour_start_at
LEFT JOIN {{ ref('isone_fuel_mix__hourly') }} AS fuel_mix ON hours.hour_start_at = fuel_mix.hour_start_at
LEFT JOIN hub_prices ON hours.hour_start_at = hub_prices.hour_start_at
LEFT JOIN {{ ref('us_holidays') }} AS holidays
    ON DATE(hours.hour_start_at, 'America/New_York') = holidays.holiday_date
