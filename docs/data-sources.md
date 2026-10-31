# Data source notes

What each source offers, how to reach it, and what exploration found. Facts here were checked on the date given; re-check before relying on one that's old.

## ISO-NE web services

ISO New England's REST API, `https://webservices.iso-ne.com/api/v1.1/`. Docs are public at `https://webservices.iso-ne.com/docs/v1.1/` (checked 2026-10-29).

- **Access:** HTTP basic auth with an ISO Express account (the account is the API access; no separate request); an unauthenticated call returns 401. The login goes in the `isone-ws-username` / `isone-ws-password` secrets ([runbook](runbook.md#add-or-rotate-a-source-credential)).
- **The public ISO Express CSV downloads** (`iso-ne.com/transform/csv/...`) return 403 to scripts, so the API is the only route for a pipeline.
- **Shape:** most feeds offer `/current` and `/day/{day}` (YYYYMMDD, an Eastern day), so a backfill is one call per feed per day, and a scheduled run asks for yesterday and today ([0010](decisions/0010-isone-day-files.md)). Add `.json` for JSON (XML otherwise). Records are nested twice (`{"GenFuelMixes": {"GenFuelMix": [...]}}`); a day with no data is `{}` or an empty list, depending on the feed.
- **Time:** Eastern time with its offset (`2026-10-30T12:00:00.000-04:00`), exact through DST.
- **Checked 2026-10-31** with the project's login:
  - **Fuel mix:** irregular snapshots, ~200 a day, one record per fuel running (`BeginDate`, `FuelCategory`, `FuelCategoryRollup`, `GenMw`, `MarginalFlag`). A fuel that isn't running is absent, not 0. Day files reach back to about 2020.
  - **Zonal load:** 288 intervals × 8 zones a day (`interval_begin_date`, `load_zone_id`, `load_zone_name`, `estimated_load_mw`, `estimated_btm_pv_mw`), nested three levels deep, in snake_case. Zones add up to system native load, and their rooftop solar to the system estimate; at noon on 2026-10-30 rooftop solar exceeded grid load in WCMA (1,086 vs. 678 MW). Day files reach back to about 2025.
  - **Prices:** ~1,300 locations (`/locations/all`); the Hub is 4000 and the load zones 4001–4008. Records nest the location (`"Location": {"@LocId": "4000", "@LocType": "HUB", "$": ".H.INTERNAL_HUB"}`) beside `LmpTotal`, `EnergyComponent`, `CongestionComponent`, `LossComponent`. Real-time finals lag about a day (Oct 29 final on Oct 31, Oct 30 not yet); preliminary five-minute data can have gaps (271 of 288 intervals on Oct 20); the hourly real-time price is the mean of the five-minute prices. Day-ahead prices for tomorrow are out by evening ([0012](decisions/0012-isone-prices.md)).
  - **System load:** 288 five-minute intervals a day (`LoadMw`, `NativeLoad`, `ArdDemand`, `SystemLoadBtmPv`, `NativeLoadBtmPv`). `SystemLoadBtmPv` adds ISO-NE's behind-the-meter (rooftop) solar estimate: 9,483 MW measured vs. 14,051 MW with rooftop solar at noon on 2026-10-30. Day files reach back to about 2024.

Feeds relevant to the roadmap (of ~440 endpoints):

| Feed | Endpoint | Use |
|---|---|---|
| Generation by fuel | `/genfuelmix/day/{day}` | What's burning: gas, nuclear, hydro, wind, solar, oil, … (ingested: `bronze.isone_fuel_mix`) |
| System load | `/fiveminutesystemload/day/{day}`, `/hourlysysload/day/{day}` | Demand, with a rooftop solar estimate (five-minute ingested: `bronze.isone_system_load`) |
| Zonal load | `/fiveminuteestimatedzonalload/day/{day}` | Demand and rooftop solar per load zone, matching the weather points (ingested: `bronze.isone_zonal_load`) |
| Real-time prices | `/fiveminutelmp/{prelim,final}/day/{day}/location/{locationId}`, `/hourlylmp/rt/{prelim,final}/day/{day}` | Prices; prelim values are replaced by final ones (five-minute ingested: `bronze.isone_rt_lmp`) |
| Day-ahead prices | `/hourlylmp/da/final/day/{day}[/location/{locationId}]` | The market's forecast of real-time prices (ingested: `bronze.isone_da_lmp`) |
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
