# 0003 — Cost guardrails from day one

**Status:** Accepted · **Date:** 2026-10-29

## Context
A few dollars a month is fine; a $50 month would be a red flag. GCP has no spending cap, and a billing kill switch would stop ingest and lose data sources don't keep ([0001](0001-append-only-bronze.md)). The MBTA project showed where cost comes from: compute per job run, and BigQuery queries that re-read growing tables every hour. It also showed that a project-wide daily query quota misfires (it refused queries far below its limit), so this project never sets one.

## Decision
- **Poll as often as the data needs, not as often as possible.** Weather runs every 6 hours, which captures each major model update. A source that returns every interval since the last call (ISO-NE) doesn't need 5-minute polling to get 5-minute data.
- **Growing bronze tables get incremental silver tables.** Each run reads only new ingest runs, via a literal `ingested_at` filter that prunes bronze's day partitions (`macros/new_ingest_runs.sql`). Views over growing bronze are only read with that filter.
- **Tests go on tables, not on views over all of bronze**, so a test doesn't rescan all history every run.
- **Per-query byte limit:** `maximum_bytes_billed` of 10 GiB (~$0.06) on every dbt query (`transform/profiles.yml`). A query that would bill more fails before it runs, and the failure emails.
- **Lean compute:** the transform runs on 1 vCPU every 6 hours, after the weather run; ingest jobs on 1 vCPU and 512 MiB.
- **Budget alerts** on the billing account, outside Terraform (the deployer has no billing access): $5/month, emailing at 50%, 90%, and 100% of actual spend, at forecast 100%, and again at 200% ($10) and 400% ($20), so a runaway is noticed well before $50.

## Consequences
- Expected cost is $0–3/month. Before adding a high-volume source (all ~1,200 ISO-NE pricing nodes, say), estimate its bronze growth and query cost first.
- Raising the transform's frequency (when ISO-NE prices arrive) is a deliberate change to `transform_schedule`, weighed against compute cost.
- The 10 GiB limit caps a `--full-refresh` of the largest incremental model. Raise it before bronze outgrows it (`docs/roadmap.md`).

**2026-11-03 — merges limited to recent partitions.** Reading only new ingest runs kept each run's *input* small, but a merge also scans the table it writes to, to match keys: with all of history in silver, a scheduled transform billed ~2 GB (fuel mix's merge alone read 318 MB to add a few thousand rows), growing with every year kept. Each incremental silver model is now partitioned by month on its time column, and merges only into the last 35 days (`incremental_predicates`, `macros/incremental_time_window.sql`): those merges now read kilobytes to ~2 MB. The 35 days cover every key a scheduled run brings; a backfill brings older keys, so rebuilding with `--full-refresh` after one ([0013](0013-isone-backfill.md)) is now required for correctness, not just completeness (otherwise its re-delivered rows are added again; the unique tests would catch that). What's left of a run's cost is mostly BigQuery's minimum of 10 MB per table per query across ~150 small model and test queries, and the gold rebuild, together ~1 GB, within the free tier.
