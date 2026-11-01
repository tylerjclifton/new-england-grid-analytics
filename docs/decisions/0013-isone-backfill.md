# 0013 — ISO-NE backfill: the scheduled jobs, run once over a day range; hourly real-time prices before 2024

**Status:** Accepted · **Date:** 2026-10-31

## Context
The scheduled ISO-NE jobs ([0010](0010-isone-day-files.md), [0012](0012-isone-prices.md)) pull yesterday and today. Models need years. Probing the API on 2026-10-31 (Hub for prices), each feed's day files start at a different point:

| Feed | First day with data (probed) |
|---|---|
| Day-ahead prices, hourly real-time prices (final) | between 2019-01 and 2019-06 |
| Fuel mix | between 2019-05 and 2019-06 |
| Five-minute real-time prices (final) | between 2024-01 and 2024-09 |
| System load (with the rooftop solar estimate) | between 2024-04 and 2024-06 |
| Zonal load | between 2025-01-15 and 2025-02-01 |

Whether these are launch dates or rolling retention windows can't be told from one look. If they roll, every day waited is a day lost for good, so backfill now ([0001](0001-append-only-bronze.md)).

Real-time prices are only five-minute from 2024, but hourly real-time prices reach back to 2019. Five years more of real-time prices (two gas-price winters among them) matter more for modeling than five-minute detail does.

## Decision
- **Backfill is a mode of each scheduled job, not separate code.** `BACKFILL_START` / `BACKFILL_END` (YYYYMMDD, inclusive), set on a one-off execution (`gcloud run jobs execute --update-env-vars`, with `--task-timeout`), replace the job's usual days (`ingest/common/isone.py`). Shaping and loading are the same code the schedule runs.
- **Batched by month.** A backfill fetches and loads 31 days at a time, so memory stays flat at 512 MiB however long the range. Batches share the run's `ingested_at`, as any run does.
- **Polite:** a 0.1 s pause between calls in backfill mode. ISO-NE sends no rate-limit headers; the largest backfill (day-ahead, ~26,000 calls) takes about two hours.
- **Real-time backfills are final prices only.** Preliminary prices for past days add nothing once finals exist.
- **Hourly real-time prices for 2019–2024** go to their own table, `bronze.isone_rt_lmp_hourly`, from a backfill-only job (`isone-rt-lmp-hourly`: no schedule; it refuses to run without a range). From 2024 on, the five-minute feed covers real time and hourly is derived from it. The overlapping months (2024) are in both, which checks that derivation.
- **Ranges start before the probed first day** (e.g. 2019-01-01): days before a feed's history return nothing and load nothing.
- **After each backfill, rebuild that feed's silver tables** (`dbt build --full-refresh --select <model>`; [runbook](../runbook.md#backfill-a-feed)). Incremental models take rows newer than the last ingest run they processed; a backfill running for hours while a scheduled transform runs could have rows stamped older than what was just processed. A full refresh reads all of that bronze table (under 1 GB), so it costs about half a cent.

## Consequences
- **Size:** about 55,000 calls and ~1 GB of bronze in all (fuel mix ~5.5M rows, five-minute prices ~2.4M, day-ahead ~0.6M, hourly real-time ~0.4M, load ~1.7M). One-off compute is a few vCPU-hours, about $0.25; storage adds about 2 cents a month.
- **A failed backfill retries the whole range** (the job's one retry), duplicating rows; silver's `__latest` models collapse duplicates, so it costs only space.
- **Re-running is safe**, for the same reason: bronze gains a version, silver keeps the newest.
- Gold combines the two real-time tables: hourly from `isone_rt_lmp_hourly` before the five-minute history, derived from `isone_rt_lmp` after.
