# 0007 — Silver models are `<bronze table>__<step>`; views unless they sit on growing bronze

**Status:** Accepted · **Date:** 2026-10-29 (carried over from mbta-reliability-analytics)

## Context
In the MBTA project, silver mixed cleaned copies, incremental tables, and multi-step logic with nothing in their names to tell them apart. dbt's conventional prefixes (`stg_`, `int_`) were rejected there: neither says what it stands for, and "staging" usually means an environment.

## Decision
**Every silver model is named `<bronze table>__<step>`:**
- **`__base`** is the cleaned copy: renamed, typed, and converted, with no business rules. For most sources that's the latest version of each record. For a forecast, every version is a record ([0009](0009-weather-per-load-zone.md)), so `openmeteo_forecast__base` keeps them all.
- **Any other step** is named for what it produces (`openmeteo_forecast__latest`), built from `__base` or earlier steps. Each applies one rule or reshaping, so it can be queried and tested on its own. A step's name shouldn't suggest a different grain.

The prefix is the source a model is about; the double underscore separates it from the step. The layer isn't in the name, since the dataset (`silver.`) says it.

**Materialization:** silver models are **views** by default, recomputed when read. A model that sits on a growing bronze table is an **incremental table** that processes only new ingest runs ([0003](0003-cost-guardrails.md)). Today that's `openmeteo_forecast__latest`.

## Consequences
- Each source's models sort together, and the lineage reads off the name.
- In production, renamed models leave their old objects behind (dbt doesn't drop them), so drop them by hand after the deploy (`bq rm`).
