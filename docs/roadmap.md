# Roadmap

Planned work, roughly in order, with why. Move an item to a [decision record](decisions/) once it's decided, and delete it once it's done.

## Next

1. **ISO-NE grid data** (waiting on the ISO Express account). One ingest job per feed, all from the web services API ([data-sources.md](data-sources.md#iso-ne-web-services)): generation by fuel (`/genfuelmix/day/{day}`), system load (`/fiveminutesystemload/day/{day}`), and real-time prices for the hub and eight load zones (`/fiveminutelmp/...`). Each run pulls every interval since the last one, so it doesn't need to poll every 5 minutes ([0003](decisions/0003-cost-guardrails.md)). Settle prelim vs. final prices in a decision record before building prices. Then a backfill of a year or more, by day.
2. **ISO-NE's own forecasts** (`/hourlyloadforecast`, `/sevendayforecast`, `/sevendaywindpowerforecast`): the benchmark a load model has to beat (EIA-930's copy of ISO-NE's day-ahead forecast was off by 3.2% on average in January–June 2026).
3. **EIA-930** (waiting on the API key, or from the free bulk files): hourly demand, the day-ahead demand forecast, and generation by fuel for ISO-NE back to July 2015, as long history for modeling. EIA regenerates its files daily, so re-pull a lookback window and keep the latest version ([0001](decisions/0001-append-only-bronze.md)).
4. **Weather backfill.** Open-Meteo's historical forecast API (past forecasts, for honest model training) and archive API (reanalysis, the best estimate of what happened), into separate bronze tables, so models have years of weather before 2026-10-29 ([0009](decisions/0009-weather-per-load-zone.md)).
5. **First gold table:** hourly × load zone, joining load, fuel mix, prices, and weather (UTC, plus local hour and date). The input to dashboards and models.
6. **Dashboard** (Streamlit on Cloud Run, scaling to zero, like the MBTA site): fuel mix, prices, load vs. temperature. Multiple pages from the start. Probably a subdomain of tylerclifton.com.

## Modeling, once history exists

- **Next-day load forecast** from forecast weather, calendar, and holidays, scored against ISO-NE's forecast.
- **Price spike prediction** (rare events: precision vs. recall).
- **Behind-the-meter solar**: the midday dip in load against irradiance, vs. ISO-NE's estimates.
- **Gas price → power price**, and the winter oil switch (oil peaked at 7,865 MW, above gas, on 2026-01-25).
- **Storm outages** from DOE EAGLE-I county outage history against wind and snow.

## Dated upkeep

| When | What |
|---|---|
| Before **2027-07-15** | Upgrade dbt (1.12 support ends); consider v2 ([0006](decisions/0006-runtime-versions.md)) |
| ~2029-10 | Python 3.13 support ends |
| When a full refresh nears 10 GiB | Raise `maximum_bytes_billed` in `transform/profiles.yml` before any `--full-refresh` ([0003](decisions/0003-cost-guardrails.md)). Weather alone takes decades; prices for every ISO-NE node would be much sooner |
