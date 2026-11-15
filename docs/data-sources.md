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
  - **History depth** (first day with data, probed 2026-10-31): day-ahead and hourly real-time prices and fuel mix from about mid-2019; five-minute real-time prices from 2024 (between January and September); system load from about mid-2024; zonal load from February 2025. Launch dates or rolling windows: not yet known ([0013](decisions/0013-isone-backfill.md)).
  - **Forecasts** ([0017](decisions/0017-isone-forecasts.md)): the `/all` load forecasts hold every version for the day's hours (`BeginDate`, `CreationDate`, `LoadMw`, `NetLoadMw`; ~10 versions system-wide, ~9 per zone, from two days before). The wind forecast is one record per publication with `MarketDays` → `MarketDateInfo` → `MarketDateData` (`HourEnding`, `WindPowerForecast`), 7 days ahead; hour endings run "01"–"24", with "02X" for the repeated hour when clocks fall back. All three reach back to at least mid-2019.
  - **System load:** 288 five-minute intervals a day (`LoadMw`, `NativeLoad`, `ArdDemand`, `SystemLoadBtmPv`, `NativeLoadBtmPv`). `SystemLoadBtmPv` adds ISO-NE's behind-the-meter (rooftop) solar estimate: 9,483 MW measured vs. 14,051 MW with rooftop solar at noon on 2026-10-30. Day files reach back to about 2024.

Feeds relevant to the roadmap (of ~440 endpoints):

| Feed | Endpoint | Use |
|---|---|---|
| Generation by fuel | `/genfuelmix/day/{day}` | What's burning: gas, nuclear, hydro, wind, solar, oil, … (ingested: `bronze.isone_fuel_mix`) |
| System load | `/fiveminutesystemload/day/{day}`, `/hourlysysload/day/{day}` | Demand, with a rooftop solar estimate (five-minute ingested: `bronze.isone_system_load`) |
| Zonal load | `/fiveminuteestimatedzonalload/day/{day}` | Demand and rooftop solar per load zone, matching the weather points (ingested: `bronze.isone_zonal_load`) |
| Real-time prices | `/fiveminutelmp/{prelim,final}/day/{day}/location/{locationId}`, `/hourlylmp/rt/{prelim,final}/day/{day}` | Prices; prelim values are replaced by final ones (five-minute ingested: `bronze.isone_rt_lmp`) |
| Day-ahead prices | `/hourlylmp/da/final/day/{day}[/location/{locationId}]` | The market's forecast of real-time prices (ingested: `bronze.isone_da_lmp`) |
| Load forecasts | `/hourlyloadforecast/all/day/{day}` (every version), `/reliabilityregionloadforecast/day/{day}/all` (per zone, every version), `/sevendayforecast/day/{day}` | ISO-NE's own forecasts: the modeling benchmark (system and zonal ingested: `bronze.isone_load_forecast`, `isone_zonal_load_forecast`) |
| Wind forecast | `/sevendaywindpowerforecast/day/{day}` | One 7-day forecast a day, by market date and hour ending (ingested: `bronze.isone_wind_forecast`) |
| Interchange | `/actualinterchange/day/{day}`, `/fiveminuteexternalflow/day/{day}` | Imports from Quebec, New York, New Brunswick |
| Grid conditions | `/powersystemconditions/...`, `/capacityscarcitycondition/day/{day}` | Capacity shortfalls and emergencies |
| Outages | `/outages/day/{day}/outageType/{outageType}` | Generator and transmission outages (not customer outages) |
| Locations | `/locations/all` | Pricing location IDs (hub, zones, nodes) |

## EIA-930 (Hourly Electric Grid Monitor)

Hourly data for every US balancing authority; ISO-NE is `ISNE`. Explored 2026-10-29 with the January–June 2026 file.

- **Access:** bulk six-month CSVs need no key: `https://www.eia.gov/electricity/gridmonitor/sixMonthFiles/EIA930_BALANCE_<year>_<Jan_Jun|Jul_Dec>.csv` (~30–47 MB each, all BAs), back to `2015_Jul_Dec`. The API (`api.eia.gov/v2/electricity/rto/{region-data,fuel-type-data}`) needs a free key (in Secret Manager since 2026-10-31) and for ISNE starts at **2019-01-01** ([0014](decisions/0014-eia-930.md)).
- **API shape:** long records, one per hour × measure: `{"period": "2019-01-01T06", "respondent": "ISNE", "type": "D", "type-name": "Demand", "value": "11614", "value-units": "megawatthours"}` (fuel type data has `fueltype` instead of `type`). Values are strings; pages hold up to 5,000 records. `period` is the UTC hour **end**, matching the bulk files' "UTC Time at End of Hour", and the values match the bulk files' raw columns hour for hour.
- **Bulk columns change over time:** 19 in 2015 (demand, forecast, net generation, interchange, no fuel breakdown), 44 in 2019, 65 in 2026. For ISNE, raw and "(Adjusted)" columns were identical in 2015 H2 and 2019 H1.
- **Revisions:** every file, back to 2015, had a Last-Modified of 2026-10-28, so EIA regenerates them all daily and any hour can change.
- **Time:** ISNE's UTC column had all 4,343 hours, no gaps or duplicates. The local-time column skips 2 AM on 2026-03-08 ([0002](decisions/0002-timestamps-in-utc.md)).
- **Columns:** demand, ISO-NE's day-ahead demand forecast, net generation, interchange, and generation by fuel, each with "Imputed" and "Adjusted" variants. A fuel the region isn't burning is often **null, not 0** (coal null 54% of hours, oil 37%), so treat null as zero only deliberately.
- **Findings, ISNE, Jan–Jun 2026:**
  - Demand averaged 13,235 MW (min 7,312, max 22,186).
  - ISO-NE's day-ahead forecast was off by 3.2% on average (MAPE): the bar for a load model.
  - Mix: gas 49%, nuclear 25%, hydro 6%, wind 6%, oil 5%, other 4%, pumped storage 2%, grid-scale solar 2%. Rooftop solar isn't in the mix; it shows up as lower demand.
  - Oil is a winter story: 2,025 MW average in January, 17 MW in March. On 2026-01-25, oil peaked at 7,865 MW, above gas (5,255 MW average that day) — gas pipelines serving heating first.
  - Net interchange averaged −1,006 MW: New England imports.

## EIA natural gas prices

Explored 2026-11-15 ([0019](decisions/0019-natural-gas-prices.md)). The same API and key as EIA-930, routes under `natural-gas/pri/`. Records have the same fields on both routes used: `period`, `duoarea`, `area-name`, `product`, `product-name`, `process`, `process-name`, `series`, `series-description`, `value` (a string, or null), `units`.

- **Henry Hub spot** (`/fut`, `frequency=daily`, `facets[series][]=RNGWHHD`): $/MMBtu, every trading day from 1997-01-07 (7,504 days), posted about weekly (Nov 11 was the latest on Nov 15). The route's futures series stop after 2024-04-05; the spot price goes on.
- **By state, monthly** (`/sum`, `frequency=monthly`, `facets[process][]`, `facets[duoarea][]=SMA`, …): `PEU` is the price delivered to electric power consumers, $/MCF. Since 2015 it exists for Massachusetts in every month, Connecticut 139 of 140, Rhode Island 101, Maine 46, New Hampshire 35 (2022–2024), Vermont none (withheld). Latest is about two months back (August on Nov 15). `PG1` (citygate) is far above it, with local delivery included: Massachusetts $19.64/MCF vs. $2.77 in August 2026.
- **New England's daily price** (Algonquin Citygates) is ICE's. EIA's wholesale page (`eia.gov/electricity/wholesale`) has ICE gas files only through 2017; electricity files (Mass Hub on-peak, day ahead) continue.
- **Speed:** on 2026-11-15 the API dropped connections and took over 60 s to answer `/sum` queries; `fetch()`'s retries got through. A facet with several values is the parameter repeated (`requests` sends a list that way); with `curl`, use `-g` so the brackets aren't read as a glob.

## DOE EAGLE-I

County-level customers without power every 15 minutes, from utilities' public outage maps, by Oak Ridge National Laboratory for DOE. Explored 2026-11-15 ([0018](decisions/0018-eaglei-outages.md)).

- **Access:** figshare article 24237376, no key. `https://api.figshare.com/v2/articles/24237376` lists the latest version's files (name, size, `download_url`). Version 4 (2026-02-25): `eaglei_outages_2014.csv` … `eaglei_outages_2025.csv`, plus `MCC.csv` (modeled customers per county, 2022), `coverage_history.csv` (customers covered per state, 2018–2022) and `DQI.csv` (a data quality index by FEMA region, 2018–2022; region 1 is New England). Downloads redirect to presigned storage URLs that accept Range requests. Speed varied from 0.07 to 4.8 MB/s on one day, and a connection dropped mid-file.
- **Files:** every US county, sorted by time; 78 MB (2014, from November) to 1.4 GB (2025, ~30 million rows). Columns `fips_code` (with the leading zero), `county`, `state` (full name), `customers_out`, `run_start_time`. The 2023 file calls `customers_out` `sum`; 2024's adds `total_customers`; 2020 has blank `customers_out` values.
- **Time** is UTC ("All data in EAGLE-I is presented in Coordinated Universal Time", Brelsford et al., *Scientific Data*, 2024).
- **No zero rows:** "Missing entries are either a customer outage value of zero or a gap in data collection", and the data doesn't say which. Outages shorter than 15 minutes may be missed.
- **New England:** 791,258 rows in 2025 (2.6% of the file; Massachusetts 262,623, Connecticut 163,365, Maine 108,560, New Hampshire 100,424, Vermont 87,357, Rhode Island 68,929). Connecticut is in its eight old counties (09001–09015) in every year, not the 2022 planning regions. Customer coverage 2018–2022 was 83–99% by state (New Hampshire's 2018 started at 17%); the region's quality index fell to 62 in 2020 (69% of runs enabled), 90–94 in other years.

## Open-Meteo

Weather APIs, no key; free for non-commercial use up to 10,000 calls/day ([0009](decisions/0009-weather-per-load-zone.md)). Checked 2026-10-29.

- **Forecast:** `api.open-meteo.com/v1/forecast`. Comma-separated latitudes and longitudes return a JSON list in request order (a single point returns an object). `timezone=GMT` gives UTC; `past_days` and `forecast_days` set the window (1 + 7 days = 192 hours).
- **Reanalysis archive:** `archive-api.open-meteo.com/v1/archive`: the best estimate of past weather, back decades, every variable; current to yesterday (checked 2026-11-01). Ingested as `bronze.openmeteo_archive` ([0015](decisions/0015-weather-history.md)).
- **Previous runs:** `previous-runs-api.open-meteo.com/v1/forecast`: for each hour, `<variable>_previous_day<N>` is what the run N days earlier forecast. Temperature from 2021 (with gaps: none on 2024-01-15); dew point, cloud cover and radiation from about 2024-02, `wind_speed_100m` from about 2024-03. Ingested as `bronze.openmeteo_previous_runs`.
- **Historical forecasts:** `historical-forecast-api.open-meteo.com/v1/forecast`: the first hours of each run stitched together, from 2016 (`wind_speed_100m` missing in 2018). Not ingested: close to the reanalysis, and not what was known a day ahead.
- Grid-cell coordinates come back snapped from the requested point (Boston 42.36, −71.06 → 42.365, −71.062).

## Not yet explored

- **NOAA hourly observations** (Global Hourly/ISD): moved to AWS (`noaa-global-hourly-pds`); an alternative to reanalysis for observed weather.
