# 0017 — ISO-NE's own forecasts: every version of the load forecasts, and the daily wind forecast, as the benchmark

**Status:** Accepted · **Date:** 2026-11-02

## Context
A forecast model is only as good as what it's compared with. EIA-930 carries one ISO-NE day-ahead demand forecast per hour, system-wide ([0014](0014-eia-930.md)). ISO-NE publishes much more (explored 2026-11-01, [data-sources.md](../data-sources.md#iso-ne-web-services)):

- **System load forecast, every version** (`/hourlyloadforecast/all/day/{day}`): for each hour, every forecast issued for it, about 10, from two days before through the day itself, each with its `CreationDate`. Noon on 2026-10-30 went 8,610 → 9,040 → 8,730 MW across its versions.
- **Load forecast per load zone, every version** (`/reliabilityregionloadforecast/day/{day}/all`): the same, for the eight load zones (ISO-NE's "reliability regions" here, named like `.Z.CONNECTICUT`), about 9 versions.
- **Seven-day wind power forecast** (`/sevendaywindpowerforecast/day/{day}`): one published each day (about 8:30 Eastern), system-wide, nested by market date and **hour ending** ("01"–"24", "02X" for the repeated hour when clocks fall back).
- History for all three reaches back to at least mid-2019 (probed 2019-06-01), like prices and fuel mix ([0013](0013-isone-backfill.md)).

## Decision
- **Three jobs** (`isone-load-forecast`, `isone-zonal-load-forecast`, `isone-wind-forecast`) on the ISO-NE schedule (every 6 hours, [0010](0010-isone-day-files.md)), into `bronze.isone_load_forecast`, `isone_zonal_load_forecast`, `isone_wind_forecast`.
- **Every version is kept.** Load forecast runs pull **yesterday** (its versions are complete) and **tomorrow** (the versions so far). Yesterday's file already holds every version issued for that day, so the history is complete with one call, and tomorrow's keeps the latest forecast current. Wind pulls yesterday's and today's publications. Silver keeps each hour × version once.
- **The benchmark is "day-ahead as issued"**: for each hour, the last version issued before **10:00 Eastern the day before**, the day-ahead market's bid deadline, when a day-ahead forecast actually has to be committed. Silver's `__day_ahead` views pick it, so a model is scored against the forecast ISO-NE had at the same moment. Other leads (two days out, same day) come from the same versions.
- **Wind hours are converted in the ingest**, not in silver: ISO-NE gives market date and hour ending, not a timestamp. Each day's list of hours is contiguous, so the ingest anchors on the day's last hour (never during a clock change) and counts back one hour per entry (`hour_starts` in `ingest/common/isone.py`). That places "02X" and spring-forward's missing hour without interpreting either. Bronze keeps `MarketDate` and `HourEnding` as received, beside the derived `BeginDate`.
- **Zones map through the location seed** by ISO-NE name (`iso_location_name`), so forecasts share the load zone codes (ME … NEMA) with everything else.

## Consequences
- **Size and cost:** ~400 (system), ~2,500 (zonal) and ~340 (wind) rows per run, ~250 MB a year in all, most of it re-pulled versions. The backfill (mid-2019 on) is ~2,700 calls per feed, one call a day each, a few hours one at a time under the request limit ([0013](0013-isone-backfill.md)). Effectively $0.
- **A load model has a fair benchmark** at every lead and in every zone, not just one system-wide day-ahead number.
- **A wind model has one at all**; nothing else here forecasts wind generation.
- The 10:00 deadline is a convention for comparing like with like; a model issued at another time should be compared with the version ISO-NE had at that time, which the `__issued` tables support.
