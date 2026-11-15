# 0019 — Natural gas prices: Henry Hub daily and New England power plants' price monthly, from EIA

**Status:** Accepted · **Date:** 2026-11-15

## Context
Gas sets New England's power price almost all the time: it was the marginal fuel in 93.2% of hours since mid-2019 (`gold.grid_hourly`). The gas → power price model ([roadmap](../roadmap.md)) needs what gas cost. What's available, explored on 2026-11-15 ([data-sources.md](../data-sources.md#eia-natural-gas-prices)):

- **New England's own daily price** (Algonquin Citygates) is ICE's data. EIA's public copies of ICE's gas prices stop at 2017, and the rest is sold. Nothing free gives a daily New England gas price after 2017.
- **Henry Hub daily spot** (EIA API, `natural-gas/pri/fut`, series `RNGWHHD`, free with the key we already hold): every trading day since 1997-01-07, $/MMBtu, posted about weekly. It's the national price, so it misses New England's winter premium, when pipelines into the region fill with heating demand.
- **Monthly prices by state** (`natural-gas/pri/sum`): the **price delivered to electric power consumers** (process `PEU`), which is what power plants paid. Massachusetts' plants paid $19.72/MCF in January 2026 and $2.77 in August: the winter premium, by month. EIA withholds it where a state has few plants. Since 2015 it exists for Massachusetts in all 140 months, Connecticut 139, Rhode Island 101, Maine 46, New Hampshire 35, Vermont none. It's published about two months after the month, and revised when the annual data comes out.
- **Citygate prices** (`PG1`) include local delivery: Massachusetts was $19.64/MCF in August 2026 against $2.77 for power plants, so they say little about generators' fuel cost.
- **The API was slow on the day explored:** dropped connections and 60-second read timeouts, all absorbed by `fetch()`'s retries. The backfill's two queries took 40 minutes.

## Decision
- **One daily job**, `eia-natural-gas-prices` (05:15, with the other EIA jobs), into `bronze.eia_natural_gas_prices`. It makes two queries, one per series kind: Henry Hub daily, and the power plant price monthly for the six New England states. Bronze keeps the API's fields (`-` as `_`), the same for both routes, plus `frequency`. `period` is a DATE: the trading day, or the month's first day.
- **Each run re-pulls** a month of the daily series and two years of the monthly one, so EIA's revisions are kept ([0001](0001-append-only-bronze.md)). Backfilled from 2015, before any hour gold has.
- **Units as reported:** $/MMBtu for Henry Hub, $/MCF for the states. Converting needs gas's heat content (about 1.04 MMBtu per MCF), which EIA publishes yearly by state; that's for a model to apply, not silver.
- **Not ingested:** citygate prices (delivery costs, above), and Algonquin's daily price (paid).
- **Silver's newest-version table merges over all of itself**, not the usual last 35 days ([0003](0003-cost-guardrails.md)), since revisions reach back two years. The table stays tiny: ~4,000 rows, growing ~350 a year.
- **In gold:** Henry Hub in `grid_hourly`, as the price of the latest trading day on or before the hour's Eastern date, at most 4 days back (enough for a weekend plus a holiday, not long enough to make a stalled feed look current). The zone's state's monthly power plant price goes in `grid_zone_hourly`; the three Massachusetts zones share Massachusetts'.

## Consequences
- **Size and cost:** ~165 rows a run, ~60,000 rows (~7 MB) a year, most of it re-pulled versions. The backfill is ~3,000 daily and ~840 monthly rows. Effectively $0.
- **Winter spikes show only monthly.** A cold week's gas price (Algonquin can run many times Henry Hub) is averaged into its month. A model can back out an implied daily gas price from the Hub's power price in hours when gas is marginal.
- **Recent months are null** in the state price until EIA publishes them, about two months on. Henry Hub's last few days are null until its weekly posting.
- **Outside Massachusetts and Connecticut the state price is patchy,** and absent in Vermont, which has almost no gas-fired generation.
