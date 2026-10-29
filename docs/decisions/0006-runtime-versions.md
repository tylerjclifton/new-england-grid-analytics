# 0006 — dbt 1.12 and Python 3.13; dbt v2 skipped for now

**Status:** Accepted · **Date:** 2026-10-29 (carried over from mbta-reliability-analytics, decided there 2026-10-22)

## Context
The goal is maximum hands-off runway with minimal upkeep. dbt has the shortest support clock of anything in the stack.

## Decision
- **dbt Core 1.12** (active support to 2027-07-15) and **Python 3.13** in every image (supported to 2029-10). Not 3.14, because dbt-bigquery 1.12 only declares support up to 3.13.
- **dbt v2** (a Rust rewrite, released 2026-09-14) was skipped. It was 5 weeks old, and every dbt version gets about a year of support, so it bought no real runway. The project parses with zero deprecations, which is v2's upgrade prerequisite.

## Consequences
- The next dbt upgrade is due before mid-2027 (consider v2 then, with dbt-autofix). See [roadmap](../roadmap.md).
- Pinned images keep running past end of support, so a lapse isn't an emergency.
