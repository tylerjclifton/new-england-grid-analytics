{#
  gold.grid_zone_hourly — one row per hour × load zone

  Every hour from 2015-07-01 (Eastern midnight) through the latest hour any
  source has, for each of ISO-NE's eight load zones: the weather at the zone's
  point, the zone's load and rooftop solar, and its prices. A source that
  doesn't cover an hour leaves its columns null; coverage starts at:
    2015-07  weather (reanalysis: the weather as it was)
    2019-06  zone real-time and day-ahead prices
    2025-02  zonal load with each zone's rooftop solar estimate

  The spread to the Hub is what this zone pays beyond the benchmark: energy
  is the same everywhere, so it's congestion and losses.

  Weather timing: Open-Meteo gives instantaneous values (temperature, dew
  point, cloud cover, wind) at its label, and sums over the hour *ending* at
  its label (irradiance, precipitation, snowfall). Each row is the hour
  starting at hour_start_at, so instantaneous values come from that label
  and the hour's sums from the next one.

  The input to the dashboard and to models of load and price by zone. A table,
  rebuilt every transform run from silver (~800,000 rows).

  Steps:
    1. hours        — every hour in range × zone (a spine)
    2. final select — the spine with weather (sums from the next label), load
                      and prices joined on hour × zone; Eastern calendar
                      columns; spread to the Hub
#}

WITH

    -- 1. Every hour from 2015-07-01 00:00 Eastern to the latest hour any source has, × zone
    hours AS (
        SELECT
            hour_start_at,
            locations.location_code AS load_zone
        FROM UNNEST(GENERATE_TIMESTAMP_ARRAY(
            TIMESTAMP '2015-07-01 04:00:00+00',
            GREATEST(
                TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR),
                (SELECT MAX(hour_start_at) FROM {{ ref('isone_da_lmp__latest') }})
            ),
            INTERVAL 1 HOUR
        )) AS hour_start_at
        CROSS JOIN {{ ref('isone_pricing_locations') }} AS locations
        WHERE locations.location_code != 'HUB'
    )

-- 2. One row per hour × zone, every source side by side
SELECT
    hours.hour_start_at,
    hours.load_zone,
    {{ eastern_calendar_columns('hours.hour_start_at') }},

    -- Weather at the zone's point (reanalysis, from 2015-07): conditions at
    -- the hour's start, and totals over the hour (from the next label)
    weather.temperature_f,
    weather.dew_point_f,
    weather.cloud_cover_pct,
    weather.wind_speed_100m_ms,
    weather_sums.solar_irradiance_w_m2,
    weather_sums.precipitation_mm,
    weather_sums.snowfall_cm,

    -- Zone load (ISO-NE, from 2025-02), MW: estimated, and with rooftop solar added back
    zonal_load.load_mw,
    zonal_load.btm_solar_mw,
    zonal_load.load_with_btm_solar_mw,

    -- The zone's prices, $/MWh, and its spread to the Hub (congestion + losses)
    rt.lmp_usd_mwh                                  AS rt_lmp_usd_mwh,
    rt.lmp_max_five_minute_usd_mwh                  AS rt_lmp_max_five_minute_usd_mwh,
    rt.congestion_usd_mwh                           AS rt_congestion_usd_mwh,
    rt.lmp_usd_mwh - hub_rt.lmp_usd_mwh             AS rt_spread_to_hub_usd_mwh,
    rt.is_final                                     AS rt_is_final,
    da.lmp_usd_mwh                                  AS da_lmp_usd_mwh
FROM hours
LEFT JOIN {{ ref('openmeteo_archive__latest') }} AS weather
    ON hours.hour_start_at = weather.hour_at AND hours.load_zone = weather.load_zone
LEFT JOIN {{ ref('openmeteo_archive__latest') }} AS weather_sums
    ON TIMESTAMP_ADD(hours.hour_start_at, INTERVAL 1 HOUR) = weather_sums.hour_at
    AND hours.load_zone = weather_sums.load_zone
LEFT JOIN {{ ref('isone_zonal_load__hourly') }} AS zonal_load
    ON hours.hour_start_at = zonal_load.hour_start_at AND hours.load_zone = zonal_load.load_zone
LEFT JOIN {{ ref('isone_rt_lmp__hourly') }} AS rt
    ON hours.hour_start_at = rt.hour_start_at AND hours.load_zone = rt.location_code
LEFT JOIN {{ ref('isone_rt_lmp__hourly') }} AS hub_rt
    ON hours.hour_start_at = hub_rt.hour_start_at AND hub_rt.location_code = 'HUB'
LEFT JOIN {{ ref('isone_da_lmp__latest') }} AS da
    ON hours.hour_start_at = da.hour_start_at AND hours.load_zone = da.location_code
