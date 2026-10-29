# 0002 — Timestamps are stored in UTC

**Status:** Accepted · **Date:** 2026-10-29

## Context
The grid runs on Eastern prevailing time: ISO-NE reports hour-ending local times, so every March has a 23-hour day (2 AM never happens) and every November a 25-hour day (1 AM happens twice). In EIA-930's ISO-NE data for January–June 2026, the UTC column had no gaps and no duplicates, while the local-time column skipped 2 AM on 2026-03-08. Joining weather, load, and prices on local time would mismatch or double-count those hours.

## Decision
- Every timestamp is stored as a UTC `TIMESTAMP`, in bronze and after. Ingest jobs request UTC where a source offers it (Open-Meteo `timezone=GMT`) and convert where it doesn't.
- Columns ending `_at` are UTC timestamps. Where a source labels hours by their end ("hour ending"), silver says which convention a column uses in its description.
- Local dates and hours (`_date`, `local_hour`) are derived in silver or gold, from UTC, with `America/New_York`.

## Consequences
- Sources join on exact instants, with no daylight-saving special cases.
- Charts and models that need local time (hour of day drives load) derive it explicitly, so the DST days show up as 23 or 25 local hours rather than as missing or duplicated data.
