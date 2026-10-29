# 0001 — Bronze is append-only; never rely on a source keeping history

**Status:** Accepted · **Date:** 2026-10-29 (carried over from mbta-reliability-analytics)

## Context
Sources revise and drop data. ISO-NE replaces preliminary prices with final ones, EIA regenerates every one of its grid files daily (all of them, back to 2015, were rewritten on 2026-10-28), and a weather forecast is gone once the next one replaces it. In the MBTA project, rebuilding a bronze table during a schema change permanently lost two months of weather the source no longer had.

## Decision
- Every ingest run **appends** what it saw to bronze. Rows are never updated or deleted.
- Silver chooses which version to use (`keep_latest_version` macro, or an incremental table where re-reading all history would cost too much; [0003](0003-cost-guardrails.md)).
- Bronze tables are deletion-protected in Terraform, and the dataset has `prevent_destroy`.
- A schema change must never require dropping or rebuilding a bronze table. Renames are done in place (BigQuery `ALTER TABLE … RENAME`) or by copy, never by Terraform replacement.

## Consequences
- Revisions are history, not overwrites: silver can show both a preliminary price and the final one, and what a forecast said before the fact ([0009](0009-weather-per-load-zone.md)).
- Bronze grows with every run. Growing tables need incremental silver models so the transform doesn't re-read them ([0003](0003-cost-guardrails.md)).
- Since rows can't be removed, a local run can't write to production bronze ([0008](0008-local-ingest-writes-dev-bronze.md)).
