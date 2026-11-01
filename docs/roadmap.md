# Roadmap

Planned work, roughly in order, with why. Move an item to a [decision record](decisions/) once it's decided, and delete it once it's done.

## Next

1. **Finish the ISO-NE backfill** ([0013](decisions/0013-isone-backfill.md)): the remaining jobs one at a time ([runbook](runbook.md#backfill-a-feed)), then a `--full-refresh` of each backfilled feed's `__latest` model. Re-probe the history start dates in a few months to learn whether they're rolling windows.
2. **ISO-NE's own forecasts** (`/hourlyloadforecast`, `/sevendayforecast`, `/sevendaywindpowerforecast`): the benchmark a load model has to beat at finer grain than EIA's daily copy (ISO-NE's day-ahead forecast averaged 2.5% error, 2019–2026, per EIA-930).
3. **Dashboard** (Streamlit on Cloud Run, scaling to zero, like the MBTA site), reading `gold.grid_hourly` and `gold.grid_zone_hourly` ([0016](decisions/0016-first-gold-tables.md)): fuel mix, prices, load vs. temperature. Multiple pages from the start. Probably a subdomain of tylerclifton.com.

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
