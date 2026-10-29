# 0009 — Weather: Open-Meteo forecasts, one point per load zone, every run kept

**Status:** Accepted · **Date:** 2026-10-29

## Context
Weather drives almost everything here: heating and cooling load, solar and wind output, gas demand in cold snaps, storm outages. Two needs pull in different directions:
- **Explaining what happened** needs the best estimate of the weather in each hour.
- **Forecasting** must train on what was known in advance. Training a day-ahead load model on actual weather is leakage: in real use only the forecast exists.

ISO-NE splits New England into eight load zones (ME, NH, VT, CT, RI, SEMA, WCMA, NEMA), and later sources (zonal load, zonal prices) use them.

Open-Meteo needs no key, returns every point in one request, takes UTC directly, and offers both a live forecast API and archives (past forecasts, reanalysis) for backfill. It's free for non-commercial use up to 10,000 calls a day; this project makes 4.

## Decision
- **One point per load zone**, at its largest population center (Portland, Manchester, Burlington, Hartford, Providence, Brockton, Worcester, Boston), since that's where demand is. The points live in `ingest/openmeteo-forecast/main.py`.
- **Snapshot the forecast every 6 hours and keep every run** (`bronze.openmeteo_forecast`): yesterday's best estimate plus 7 days ahead. Bronze then holds, for any hour, every forecast made of it and when, which is our own forecast archive from 2026-10-29 on.
- Silver separates the two uses: `openmeteo_forecast__latest` is the best estimate per hour; forecasts at a given lead time come from `openmeteo_forecast__base` by `lead_hours`.
- Bronze keeps Open-Meteo's metric units. Silver converts temperature to °F (ISO-NE's convention and the usual basis for degree days), and keeps wind in m/s (the turbine convention) and irradiance in W/m².

## Consequences
- ~1,500 rows per run, ~2.2 million rows (~300 MB) a year: negligible to store, and `__latest` reads only new runs ([0003](0003-cost-guardrails.md)).
- History before 2026-10-29 needs a backfill from Open-Meteo's archives, which is a separate job (roadmap).
- A city stands in for a whole zone. That's coarse for large zones (Maine), and a population-weighted average of several points per zone is a possible refinement once a model shows it matters.
