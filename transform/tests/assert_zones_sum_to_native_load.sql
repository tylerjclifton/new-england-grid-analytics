{#
  ISO-NE's eight zonal loads add up to its system native load (within 0.06%
  on average on 2026-11-02, with 13 of 15,386 hours more than 1% off;
  docs/data-quality.md lists them). A new hour more than 1% off means a zone
  or the system feed changed.

  Checks the last 10 days only, so it warns about new data, not the known
  historical exceptions every run. Fails (warns) with each hour that
  disagrees. Warn, not error: a cross-check between feeds, not a fault in
  either one to block on.
#}

{{ config(severity='warn') }}

WITH

    zones AS (
        SELECT
            hour_start_at,
            SUM(load_mw)  AS zone_load_mw,
            COUNT(*)      AS zone_count
        FROM {{ ref('isone_zonal_load__hourly') }}
        GROUP BY hour_start_at
    )

SELECT
    zones.hour_start_at,
    zones.zone_load_mw,
    system_load.native_load_mw,
    ROUND((zones.zone_load_mw - system_load.native_load_mw) / system_load.native_load_mw * 100, 2) AS pct_difference
FROM zones
INNER JOIN {{ ref('isone_system_load__hourly') }} AS system_load
    ON zones.hour_start_at = system_load.hour_start_at
WHERE zones.zone_count = 8
  AND ABS(zones.zone_load_mw - system_load.native_load_mw) / system_load.native_load_mw > 0.01
  AND zones.hour_start_at >= TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), HOUR), INTERVAL 10 DAY)
