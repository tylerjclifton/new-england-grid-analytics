# 0016 — First gold tables: hourly spines with every source joined, system-wide and by load zone

**Status:** Accepted · **Date:** 2026-11-01

## Context
Silver has each source cleaned on its own terms: five-minute load and prices, irregular fuel mix snapshots, EIA hours labelled by their end, weather hours with sums labelled by their end, and history starting in different years (2015 for EIA and weather, 2019 for prices and fuel mix, 2024–2025 for load with rooftop solar). The dashboard and models need them side by side, on one clock.

## Decision
- **Two gold tables, one per grain:** `gold.grid_hourly` (one row per hour, New England as a whole) and `gold.grid_zone_hourly` (one row per hour × load zone). They hold what's measured system-wide (fuel mix, EIA, system load, Hub prices) and what's measured by zone (zone load and prices, weather), with no estimate allocating one to the other.
- **The hour is the common grain**, stored as a UTC hour start, with Eastern date, hour, weekday and weekend derived (`macros/eastern_calendar_columns.sql`, [0002](0002-timestamps-in-utc.md)).
- **An hour spine**, from 2015-07-01 00:00 Eastern to the latest hour any source has (tomorrow, once day-ahead prices are out), with every source left-joined. A source that doesn't cover an hour shows as null; no hour is dropped, so gaps stay visible.
- **The rollups to the hour are silver steps** (views: `isone_system_load__hourly`, `isone_zonal_load__hourly`, `isone_fuel_mix__hourly`, `isone_rt_lmp__hourly`), each defined once, so gold only joins:
  - five-minute load and prices: the hour's mean (ISO-NE's own hourly price is that mean, [0012](0012-isone-prices.md)), plus the highest five-minute price, where spikes show;
  - real-time prices before 2024 from the hourly backfill ([0013](0013-isone-backfill.md)), five-minute after;
  - fuel mix: each fuel's mean over the hour's snapshots, **an absent fuel counted as 0** (it isn't running), and the marginal fuel as the one marginal in most of the hour's snapshots;
  - weather: instantaneous values (temperature, dew point, cloud cover, wind) at the hour's start, and the hour's sums (irradiance, precipitation, snowfall) from Open-Meteo's next label, since it labels sums by the hour's end.
- **Gold weather is the reanalysis** (what the weather was). A model that predicts ahead reads forecasts as issued from silver instead ([0015](0015-weather-history.md)).
- **Tables rebuilt every run**, tested for their grain (one row per hour, or hour × zone). Value ranges are tested in silver, where each value originates.

## Consequences
- **Size and cost:** ~100,000 and ~800,000 rows; a rebuild reads ~190 MB of silver, so ~23 GB a month at four runs a day, within BigQuery's free monthly terabyte. Make them incremental if that grows past a few dollars a month.
- **Coverage differs by column**, and the table descriptions say from when. A model choosing its training window picks the columns it needs first.
- **A snapshot mean isn't a time-weighted average:** fuel mix snapshots are moments at irregular times, so the hourly MW is close to the hour's energy, not exact.
- **Next in gold:** the forecast-as-issued weather beside the actual, once a model needs it.

**2026-11-02 — holidays added.** Both tables carry `holiday_name`, `is_nerc_holiday` and `is_federal_holiday`, joined on the Eastern date from a seed (`transform/seeds/us_holidays.csv`, 2015–2035, generated from rules by `scripts/generate-holidays.py`). Two flags, because they behave differently: across 2015–2026, demand on NERC's six holidays averaged 13,022 MW, 5.8% under ordinary weekdays (13,828) and close to a Saturday (12,783), while the other federal holidays averaged 13,730, barely different from a weekday. A load model should treat them apart.
