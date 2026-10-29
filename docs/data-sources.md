# Data source notes

What each source offers, how to reach it, and what exploration found. Facts here were checked on the date given; re-check before relying on one that's old.

## ISO-NE web services

ISO New England's REST API, `https://webservices.iso-ne.com/api/v1.1/`. Docs are public at `https://webservices.iso-ne.com/docs/v1.1/` (checked 2026-10-29).

- **Access:** HTTP basic auth with an ISO Express account; an unauthenticated call returns 401. The login goes in the `isone-ws-username` / `isone-ws-password` secrets ([runbook](runbook.md#add-or-rotate-a-source-credential)).
- **The public ISO Express CSV downloads** (`iso-ne.com/transform/csv/...`) return 403 to scripts, so the API is the only route for a pipeline.
- **Shape:** most feeds offer `/current` and `/day/{day}` (YYYYMMDD), so a backfill is one call per feed per day, and a scheduled run can ask for today and yesterday and keep what's new.

Feeds relevant to the roadmap (of ~440 endpoints):

| Feed | Endpoint | Use |
|---|---|---|
| Generation by fuel | `/genfuelmix/day/{day}` | What's burning: gas, nuclear, hydro, wind, solar, oil, … |
| System load | `/fiveminutesystemload/day/{day}`, `/hourlysysload/day/{day}` | Demand |
| Zonal load | `/fiveminuteestimatedzonalload/day/{day}` | Demand per load zone (matches the weather points) |
| Real-time prices | `/fiveminutelmp/{Type}/day/{day}/location/{locationId}`, `/hourlylmp/rt/{prelim,final}/day/{day}` | Prices; prelim values are replaced by final ones |
| Day-ahead prices | `/hourlylmp/da/final/day/{day}` | The market's forecast of real-time prices |
| Load forecasts | `/hourlyloadforecast/day/{day}`, `/sevendayforecast/day/{day}`, `/reliabilityregionloadforecast/day/{day}` | ISO-NE's own forecasts: the modeling benchmark |
| Wind forecast | `/sevendaywindpowerforecast/day/{day}` | |
| Interchange | `/actualinterchange/day/{day}`, `/fiveminuteexternalflow/day/{day}` | Imports from Quebec, New York, New Brunswick |
| Grid conditions | `/powersystemconditions/...`, `/capacityscarcitycondition/day/{day}` | Capacity shortfalls and emergencies |
| Outages | `/outages/day/{day}/outageType/{outageType}` | Generator and transmission outages (not customer outages) |
| Locations | `/locations/all` | Pricing location IDs (hub, zones, nodes) |

## EIA-930 (Hourly Electric Grid Monitor)

Hourly data for every US balancing authority; ISO-NE is `ISNE`. Explored 2026-10-29 with the January–June 2026 file.

- **Access:** bulk six-month CSVs need no key: `https://www.eia.gov/electricity/gridmonitor/sixMonthFiles/EIA930_BALANCE_<year>_<Jan_Jun|Jul_Dec>.csv` (~30–47 MB each, all BAs), back to `2015_Jul_Dec`. The API (`api.eia.gov/v2/electricity/rto/...`) needs a free key.
- **Revisions:** every file, back to 2015, had a Last-Modified of 2026-10-28, so EIA regenerates them all daily and any hour can change.
- **Time:** ISNE's UTC column had all 4,343 hours, no gaps or duplicates. The local-time column skips 2 AM on 2026-03-08 ([0002](decisions/0002-timestamps-in-utc.md)).
- **Columns:** demand, ISO-NE's day-ahead demand forecast, net generation, interchange, and generation by fuel, each with "Imputed" and "Adjusted" variants. A fuel the region isn't burning is often **null, not 0** (coal null 54% of hours, oil 37%), so treat null as zero only deliberately.
- **Findings, ISNE, Jan–Jun 2026:**
  - Demand averaged 13,235 MW (min 7,312, max 22,186).
  - ISO-NE's day-ahead forecast was off by 3.2% on average (MAPE): the bar for a load model.
  - Mix: gas 49%, nuclear 25%, hydro 6%, wind 6%, oil 5%, other 4%, pumped storage 2%, grid-scale solar 2%. Rooftop solar isn't in the mix; it shows up as lower demand.
  - Oil is a winter story: 2,025 MW average in January, 17 MW in March. On 2026-01-25, oil peaked at 7,865 MW, above gas (5,255 MW average that day) — gas pipelines serving heating first.
  - Net interchange averaged −1,006 MW: New England imports.

## Open-Meteo

Weather APIs, no key; free for non-commercial use up to 10,000 calls/day ([0009](decisions/0009-weather-per-load-zone.md)). Checked 2026-10-29.

- **Forecast:** `api.open-meteo.com/v1/forecast`. Comma-separated latitudes and longitudes return a JSON list in request order (a single point returns an object). `timezone=GMT` gives UTC; `past_days` and `forecast_days` set the window (1 + 7 days = 192 hours).
- **Historical forecasts:** `historical-forecast-api.open-meteo.com/v1/forecast` (past forecasts, for training models on what was known at the time).
- **Reanalysis archive:** `archive-api.open-meteo.com/v1/archive` (best estimate of past weather, back decades, a few days' lag).
- Grid-cell coordinates come back snapped from the requested point (Boston 42.36, −71.06 → 42.365, −71.062).

## Not yet explored

- **NOAA hourly observations** (Global Hourly/ISD): moved to AWS (`noaa-global-hourly-pds`); an alternative to reanalysis for observed weather.
- **DOE EAGLE-I**: county-level customers without power, 15-minute, as yearly files. For the storm outage model.
- **Gas prices**: EIA publishes Henry Hub daily; New England's Algonquin citygate price mostly isn't free.
