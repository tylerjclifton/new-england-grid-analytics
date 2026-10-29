# 0008 — Local ingest runs write to dev_bronze

**Status:** Accepted · **Date:** 2026-10-29 (carried over from mbta-reliability-analytics)

## Context
dbt has sandboxes: local builds (`--target local`) write to `dev_silver` and `dev_gold` and read the real bronze. Ingest jobs need one too. Bronze rows are never deleted ([0001](0001-append-only-bronze.md)), so a bug tried out on a laptop must not be able to leave permanent rows in production.

## Decision
- A **`dev_bronze`** dataset holds a copy of every bronze table, built in Terraform from the same schema definitions (`local.bronze_tables` in `infra/bigquery.tf`), so the two can't drift.
- **`append_to_bronze()` defaults to `dev_bronze`.** The Cloud Run jobs set `BQ_DATASET_ID=bronze` explicitly (`infra/cloud-run-jobs.tf`). Writing real bronze is something only the deployed jobs do: to run one now, use `gcloud run jobs execute` (runbook).
- Test rows expire after 7 days by **partition**. dev_silver and dev_gold expire whole tables instead, which dbt recreates on the next build.

## Consequences
- A local ingest run is safe by default, and still loads against the production schema, so schema mistakes fail the load.
- dbt doesn't read dev_bronze. To see a local ingest run's rows, query `dev_bronze.<table>`.
