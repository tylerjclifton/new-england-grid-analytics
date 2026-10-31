# 0012 — ISO-NE prices: five-minute real-time (preliminary, then final) and hourly day-ahead, at the Hub and the eight load zones

**Status:** Accepted · **Date:** 2026-10-31

## Context
ISO-NE prices power by location (locational marginal prices, LMPs, in $/MWh). Each price is energy + congestion + losses: energy is the same across New England, while congestion is what makes one zone pricier than another when transmission limits bind. There are two markets:
- **Real-time:** the price actually paid, every five minutes. It's published as *preliminary* within minutes and replaced by a *final* price about a day later.
- **Day-ahead:** clears around midday for the next day, hourly, final when published. It's the market's forecast of real-time prices.

Exploring the API on 2026-10-31 ([data-sources.md](../data-sources.md#iso-ne-web-services)):
- **Locations:** ~1,300 pricing locations, ~1,200 of them individual network nodes. The **Hub** (4000, New England's benchmark price) and the **eight load zones** (4001–4008, the same IDs the zonal load feed uses) are the ones that match how this project is organized (by load zone, [0009](0009-weather-per-load-zone.md)). An all-locations day-ahead file is 6 MB a day.
- **Final lag:** on Oct 31, real-time finals existed through Oct 29; Oct 30 was still preliminary.
- **Preliminary vs. final:** on the days compared (Hub, Oct 20 and 25), every preliminary value equaled its final one. But preliminary five-minute data can have gaps: Oct 20 had 271 of 288 intervals preliminary, all 288 final.
- **Hourly vs. five-minute:** ISO-NE's hourly real-time price is the mean of its twelve five-minute prices (Boston, Oct 29: within a cent every hour). Spikes average out: that day's five-minute peak was $74.81, the hourly peak $61.08.

## Decision
- **Locations: the Hub and the eight load zones** (`PRICING_LOCATIONS` in `ingest/common/isone.py`). One call per day × location. Individual nodes wait for a use that needs them, sized first ([0003](0003-cost-guardrails.md)).
- **Real-time prices at five minutes, not hourly** (`isone-rt-lmp` → `bronze.isone_rt_lmp`): hourly is derived downstream, and spikes survive.
- **Both versions, in one table, labelled.** Each run pulls *preliminary* prices for yesterday and today and *final* prices for 2 and 3 days ago; `LmpType` records which. The windows never share a day, so a day arrives as preliminary, then as final. Silver prefers final, then the newest run ([0001](0001-append-only-bronze.md) keeps both).
- **Day-ahead prices hourly** (`isone-da-lmp` → `bronze.isone_da_lmp`), today and tomorrow each run. Tomorrow is empty until the market clears; the 18:10 run picks it up.
- **Same cadence as the other ISO-NE feeds:** every 6 hours ([0010](0010-isone-day-files.md)). Every interval arrives either way; a faster cadence would only make preliminary prices fresher.

## Consequences
- **Size and cost:** real-time ~9,900 rows per run (~14M rows, ~1.5 GB a year); day-ahead ~440 rows per run (~65 MB a year). Each run is ~10 seconds of HTTP calls. Storage is a few cents a month after a year, and incremental silver reads only new partitions. It's the largest table so far, so it's the one that will first approach the 10 GiB full-refresh limit (in ~6 years; [roadmap](../roadmap.md)).
- **If finals run more than 3 days late** (holidays, price corrections), those intervals stay preliminary in silver. That's acceptable given how rarely the values differ; widen the final window if it shows up.
- **Price questions this answers:** zone spreads and congestion (vs. the Hub), day-ahead vs. real-time (how well the market forecasts), and five-minute spikes. Node-level questions it can't.
- **Backfill** (later) is final prices only, by day and location.
