"""
Ingest: Open-Meteo past forecasts as they were issued, 1 and 2 days ahead, one
point per ISO-NE load zone — backfill only

Source:     Open-Meteo previous runs API (previous-runs-api.open-meteo.com, no
            key; decision 0015). For each hour, `<variable>_previous_day<N>` is
            the value forecast by the model run N days earlier. Temperature
            reaches back to 2021; the other variables start in early 2024, and
            are null before.
Cadence:    None. Run as a one-off backfill (BACKFILL_START / BACKFILL_END,
            common/backfill.py) for the years before 2026-10-29; from then on
            openmeteo-forecast keeps every forecast run itself (decision 0009).
Each run:   Each month of the range: every point's 1- and 2-day-ahead values
            for every variable, one row per lead.
Writes to:  bronze.openmeteo_previous_runs (append) — one row per load zone ×
            hour × lead × run

These are what a day-ahead model may train on: what was forecast at the time,
not what happened (that's openmeteo_archive).
"""

# Import third party libraries
import pandas

# Import shared ingest helpers
from common.backfill import backfill_batches, is_backfill, pause
from common.load import append_to_bronze
from common.openmeteo import BACKFILL_PAUSE_SECONDS, HOURLY_VARIABLES, fetch_points, to_frame
from common.run import fail

PREVIOUS_RUNS_URL = 'https://previous-runs-api.open-meteo.com/v1/forecast'

# Days ahead the forecasts were issued (each lead is one request variable per
# variable: temperature_2m_previous_day1, …)
LEAD_DAYS = [1, 2]
REQUESTED = [f"{variable}_previous_day{lead}" for lead in LEAD_DAYS for variable in HOURLY_VARIABLES]

# Backfill only: the forecast job has kept every run since 2026-10-29
if not is_backfill():
    fail("openmeteo-previous-runs runs only as a backfill: set BACKFILL_START and BACKFILL_END (docs/runbook.md)")

# One month at a time
for batch in backfill_batches():

    # ── Fetch ─────────────────────────────────────────────────────────────────

    points = fetch_points(PREVIOUS_RUNS_URL, {
        'hourly':     ','.join(REQUESTED),
        'start_date': batch[0].isoformat(),
        'end_date':   batch[-1].isoformat(),
    })

    # ── Shape ─────────────────────────────────────────────────────────────────

    # Wide (every variable × lead) → one row per lead, under the plain variable names
    wide = to_frame(points, REQUESTED)
    point_columns = [column for column in wide.columns if column not in REQUESTED]
    df = pandas.concat([
        wide[point_columns + [f"{variable}_previous_day{lead}" for variable in HOURLY_VARIABLES]]
        .rename(columns={f"{variable}_previous_day{lead}": variable for variable in HOURLY_VARIABLES})
        .assign(lead_days=lead)
        for lead in LEAD_DAYS
    ], ignore_index=True)

    # ── Write ─────────────────────────────────────────────────────────────────

    append_to_bronze(df)
    pause(BACKFILL_PAUSE_SECONDS)
