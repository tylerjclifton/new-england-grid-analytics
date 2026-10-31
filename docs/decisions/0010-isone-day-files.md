# 0010 — ISO-NE: whole-day pulls every 6 hours, source names in bronze

**Status:** Accepted · **Date:** 2026-10-31

## Context
ISO-NE's web services API ([data-sources.md](../data-sources.md#iso-ne-web-services)) is the grid's own record of what it burns, carries, and charges. The first two feeds are generation by fuel and five-minute system load. Exploring them on 2026-10-31:

- **Access:** HTTP basic auth with the ISO Express login; no separate API sign-up.
- **Shape:** each feed has `/day/YYYYMMDD.json` (an Eastern day) returning every record for that day, nested twice (`{"GenFuelMixes": {"GenFuelMix": [...]}}`). A day with no data is `{}` or an empty list, depending on the feed.
- **Time:** Eastern time with its offset (`2026-10-30T12:00:00.000-04:00`), so conversion to UTC is exact through DST.
- **Fuel mix:** irregular snapshots, ~200 a day (about every 7 minutes), one record per fuel running. A fuel that isn't running is left out, not listed at 0 (oil appeared in 35 of 211 snapshots on 2026-10-30). Each record flags whether that fuel was marginal (setting the price).
- **System load:** 288 intervals a day, including ISO-NE's estimate of behind-the-meter (rooftop) solar: `SystemLoadBtmPv` is load plus that estimate. At noon on 2026-10-30, load was 9,483 MW and load plus rooftop solar 14,051 MW, so rooftop solar covered about a third of midday demand.
- **History:** fuel mix day files reach back to about 2020 (2018 was empty); system load to about 2024 (2022 was empty).

## Decision
- **One job per feed** (`isone-fuel-mix`, `isone-system-load`), sharing `ingest/common/isone.py` for the login, the days to ask for, and unwrapping responses.
- **Each run pulls whole Eastern days: yesterday and today** (`LOOKBACK_DAYS = 2`), every 6 hours at :10, ahead of the transform at :20. A day file holds every interval, so the cadence sets how fresh the data is, not how complete (decision [0003](0003-cost-guardrails.md)). Re-pulling yesterday catches the hours after its last run, and any revision ISO-NE makes. Silver keeps the latest version of each record ([0001](0001-append-only-bronze.md)).
- **Bronze keeps ISO-NE's field names** (`BeginDate`, `GenMw`, `SystemLoadBtmPv`), as for every source; silver renames them. `BeginDate` is stored as a UTC TIMESTAMP ([0002](0002-timestamps-in-utc.md)).
- **A changed API fails the job.** A record missing an expected field stops the load (with an alert) rather than writing nulls.
- **Absent fuels stay absent in bronze.** Filling them with zeros is a modeling choice, made in gold.

## Consequences
- **Size and cost:** fuel mix adds ~3,000 rows per run (~4.4M rows, ~330 MB a year); system load ~430 rows per run (~0.6M rows, ~50 MB a year). Each run is two small HTTP calls on 1 vCPU. Storage stays under a cent a month for years, and incremental silver reads only new day partitions. Effectively $0.
- **Duplication is deliberate:** a record appears once per run that saw it (up to ~8 times). That is what lets silver see revisions; `__latest` models collapse it.
- **Backfill** is the same job with a larger `LOOKBACK_DAYS` (one call per feed per day), to be sized before it runs: about 2,000 days of fuel mix, about 900 of load.
- **Rooftop solar** needs no estimate of our own to start with: measured and solar-adjusted demand both come from ISO-NE.

**2026-10-31 — zonal load added the same way.** `/fiveminuteestimatedzonalload/day/{day}` → `isone-zonal-load` → `bronze.isone_zonal_load`: 288 intervals × 8 zones a day, each with estimated load and a rooftop solar estimate; the zones add up to system native load and the system solar estimate. It nests records three levels deep and uses snake_case names (`interval_begin_date`), so `records()` unwraps any depth and `to_frame()` takes the time column's name. History reaches back to about 2025. ~3,500 rows per run, ~400 MB a year.
