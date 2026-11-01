# Roadmap

Planned work, roughly in order, with why. Move an item to a [decision record](decisions/) once it's decided, and delete it once it's done.

## Next

1. **ISO-NE backfill** ([0013](decisions/0013-isone-backfill.md)): run each job's backfill ([runbook](runbook.md#backfill-a-feed)), rebuild silver, and add silver models for `isone_rt_lmp_hourly`. Re-probe the history start dates in a few months to learn whether they're rolling windows.
2. **ISO-NE's own forecasts** (`/hourlyloadforecast`, `/sevendayforecast`, `/sevendaywindpowerforecast`): the benchmark a load model has to beat (EIA-930's copy of ISO-NE's day-ahead forecast was off by 3.2% on average in January–June 2026).
3. **EIA-930** ([0014](decisions/0014-eia-930.md)): ingesting daily, with silver models; the API backfill (2019 on) is in. Left: the bulk backfill (2015–2018) and a `--full-refresh` of `eia_region_data__latest` after it.
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
