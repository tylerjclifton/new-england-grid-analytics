# Roadmap

Planned work, roughly in order, with why. Move an item to a [decision record](decisions/) once it's decided, and delete it once it's done.

## Next

1. **Outages and gas prices into silver and gold** ([0018](decisions/0018-eaglei-outages.md), [0019](decisions/0019-natural-gas-prices.md)): backfill both, then the county seed, silver models, and their columns in gold. That completes the data the models below need.
2. **Models** (below), now that history exists: from 2015 for demand and weather, mid-2019 for prices, fuel mix and ISO-NE's forecasts.
3. **Dashboard** (Streamlit on Cloud Run, scaling to zero, like the MBTA site), reading `gold.grid_hourly` and `gold.grid_zone_hourly` ([0016](decisions/0016-first-gold-tables.md)): fuel mix, prices, load vs. temperature, and the models' results. Multiple pages from the start. Served at a path under tylerclifton.com (e.g. `/ne-power-grid`), behind a small proxy shared with the MBTA site, rather than a subdomain.

## Models

- **Next-day load forecast** from forecast weather, calendar, and holidays, scored against ISO-NE's forecast.
- **Price spike prediction** (rare events: precision vs. recall).
- **Behind-the-meter solar**: the midday dip in load against irradiance, vs. ISO-NE's estimates.
- **Gas price → power price**, and the winter oil switch (oil peaked at 7,865 MW, above gas, on 2026-01-25).
- **Storm outages** from DOE EAGLE-I county outage history against wind and snow.

## Dated upkeep

| When | What |
|---|---|
| Each **February** | Backfill the year just posted to EAGLE-I, then rebuild its silver ([runbook](runbook.md#backfill-a-feed), [0018](decisions/0018-eaglei-outages.md)) |
| ~**2027-02** | Re-probe ISO-NE's history start dates ([0013](decisions/0013-isone-backfill.md)): a first day that has moved since 2026-10-31 means a rolling window, so history before it exists only in bronze |
| Before **2027-07-15** | Upgrade dbt (1.12 support ends); consider v2 ([0006](decisions/0006-runtime-versions.md)) |
| ~2029-10 | Python 3.13 support ends |
| When a full refresh nears 10 GiB | Raise `maximum_bytes_billed` in `transform/profiles.yml` before any `--full-refresh` ([0003](decisions/0003-cost-guardrails.md)). Weather alone takes decades; prices for every ISO-NE node would be much sooner |
