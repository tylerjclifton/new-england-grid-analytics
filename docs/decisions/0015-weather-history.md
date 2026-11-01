# 0015 — Weather history: reanalysis from 2015 for what happened, past forecasts from 2021 for what was known

**Status:** Accepted · **Date:** 2026-11-01

## Context
The forecast job ([0009](0009-weather-per-load-zone.md)) keeps every forecast run from 2026-10-29 on. Models need years of weather, and **two different kinds**:
- **What the weather was**, to explain load and prices after the fact. That's the reanalysis.
- **What was forecast at the time**, to train a model that predicts ahead. A load model trained on actual weather looks better in a backtest than it can ever be in production, because at prediction time it only has a forecast.

Open-Meteo has three history APIs. Probed 2026-11-01, at Boston:

| API | What it is | Coverage |
|---|---|---|
| Archive (`archive-api.open-meteo.com/v1/archive`) | Reanalysis (ERA5-based): one consistent best estimate of past weather | Decades back, every variable, current to yesterday |
| Historical forecast (`historical-forecast-api.open-meteo.com`) | The first hours of each forecast run, stitched into one series | 2016 on (`wind_speed_100m` missing in 2018) |
| Previous runs (`previous-runs-api.open-meteo.com/v1/forecast`) | For each hour, what the run *N days earlier* forecast (`temperature_2m_previous_day1`, …) | Temperature from 2021 (with gaps, e.g. none on 2024-01-15); every other variable from about 2024-02/03 |

## Decision
- **Reanalysis, from 2015-07** (`openmeteo-archive` → `bronze.openmeteo_archive`), to match EIA's demand history ([0014](0014-eia-930.md)). It runs daily, re-pulling the last two weeks through yesterday, since the newest days are refined; bronze keeps every version. Backfilled from 2015-07-01.
- **Past forecasts 1 and 2 days ahead, 2021 to 2026-10-28** (`openmeteo-previous-runs` → `bronze.openmeteo_previous_runs`, one row per hour × lead). Backfill only: from 2026-10-29 the forecast job's own snapshots cover forecasts at every lead. Variables Open-Meteo doesn't have for a period stay null.
- **The historical forecast API is skipped.** Its stitched first hours are close to what happened (the reanalysis covers that) but aren't what was known a day ahead (previous runs covers that).
- **Same points, variables and units as the forecast**, shared through `ingest/common/openmeteo.py`, so the three tables line up column for column.
- **Gentle on Open-Meteo's weighted limits** (600 a minute, 5,000 an hour, 10,000 a day; a month for eight points is 15–30 weighted calls): backfills make one month-sized call every 6 seconds.

## Consequences
- **Size and cost:** reanalysis ~70,000 rows a year (~800,000 back to 2015), plus ~2,700 rows per daily run; previous runs ~820,000 rows once. Under 200 MB in all; about 140 + 70 calls to backfill (~4,000 weighted, within one day's limit). Effectively $0.
- **A day-ahead load model can be backtested honestly on temperature from 2021, and on every variable from early 2024.** Before that, a model trained on reanalysis is an upper bound, and has to be labelled as one.
- **Leads are approximate:** `previous_day1` is the run about 24 hours earlier, not a fixed issue time like "9 AM the day before". For the exact timing a market uses, the forecast job's snapshots (from 2026-10-29) are the record.
