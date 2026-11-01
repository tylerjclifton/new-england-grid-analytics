# Runbook

How to do the things that come up. Commands assume the `grid` gcloud configuration ([setup](setup.md#3-sign-in-to-google-cloud)) and region `us-east1`.

## Check that alert emails work

Each job's alert policy emails on a log entry with `jsonPayload.event="job_failed"` (`infra/monitoring.tf`). To see one arrive, write a matching entry by hand:

```bash
gcloud logging write test-failure \
  '{"severity":"ERROR","event":"job_failed","job":"transform","message":"Test alert — ignore"}' \
  --payload-type=json --severity=ERROR
```

This lands under the `global` resource, not `cloud_run_job`, so it doesn't match the real policies. To test end to end instead, run a job with a setting that makes it fail (for example `--update-env-vars FORECAST_DAYS=99` on the weather job, which Open-Meteo rejects) and wait for the email, typically within 5 minutes.

## Run a job now

```bash
gcloud run jobs execute ingest-openmeteo-forecast --region=us-east1 --wait
gcloud run jobs execute ingest-isone-fuel-mix --region=us-east1 --wait
gcloud run jobs execute ingest-isone-system-load --region=us-east1 --wait
gcloud run jobs execute ingest-isone-zonal-load --region=us-east1 --wait
gcloud run jobs execute ingest-isone-rt-lmp --region=us-east1 --wait
gcloud run jobs execute ingest-isone-da-lmp --region=us-east1 --wait
gcloud run jobs execute transform --region=us-east1 --wait
```

This writes to production bronze. A local run (`PYTHONPATH=ingest python ingest/<job>/main.py`) writes to `dev_bronze` instead ([0008](decisions/0008-local-ingest-writes-dev-bronze.md)). ISO-NE jobs also need the login in the environment; read it from Secret Manager for that one command, so it isn't saved anywhere:

```bash
ISONE_WS_USERNAME=$(gcloud secrets versions access latest --secret=isone-ws-username) \
ISONE_WS_PASSWORD=$(gcloud secrets versions access latest --secret=isone-ws-password) \
PYTHONPATH=ingest python ingest/isone-fuel-mix/main.py
```

## Add or rotate a source credential

Terraform owns the secrets (`infra/secrets.tf`); the values are added by hand so they never appear in code or state:

```bash
printf '%s' "<value>" | gcloud secrets versions add isone-ws-username --data-file=-
printf '%s' "<value>" | gcloud secrets versions add isone-ws-password --data-file=-
printf '%s' "<value>" | gcloud secrets versions add eia-api-key --data-file=-
```

Jobs read `latest` at startup, so the next run picks up a new value. After rotating, disable the old version: `gcloud secrets versions disable <n> --secret=<secret>`.

## Backfill a feed

Every ISO-NE job has a backfill mode ([0013](decisions/0013-isone-backfill.md)): one execution with a day range pulls that range a month at a time, instead of yesterday and today. The override applies to that execution only; the job's schedule is untouched.

```bash
# Example: fuel mix from 2019 (days before a feed's history load nothing)
gcloud run jobs execute ingest-isone-fuel-mix --region=us-east1 --task-timeout=3h \
  --update-env-vars=BACKFILL_START=20190101,BACKFILL_END=20261031
```

| Job | Range used on 2026-10-31 | Calls | Rough time |
|---|---|---|---|
| `ingest-isone-fuel-mix` | 20190101–20261031 | ~2,900 | 15 min |
| `ingest-isone-system-load` | 20240101–20261031 | ~1,000 | 5 min |
| `ingest-isone-zonal-load` | 20250101–20261031 | ~670 | 5 min |
| `ingest-isone-rt-lmp` (final only) | 20240101–20261028 | ~9,300 | 40 min |
| `ingest-isone-rt-lmp-hourly` (backfill only) | 20190101–20241231 | ~19,700 | 1.5 h |
| `ingest-isone-da-lmp` | 20190101–20261101 | ~25,700 | 2 h |

Add `--async` to start it and return; follow it in Cloud Run → Jobs → the job → Executions. Then **rebuild that feed's silver** so no backfilled row is skipped (see the next section): e.g. `--select isone_fuel_mix__latest`. Check the result with a count by month in bronze and silver.

## Rebuild an incremental silver table

Incremental tables (`silver.openmeteo_forecast__latest`) process only new ingest runs. If a logic change needs history reprocessed, rebuild the table from bronze (cheap: weather bronze grows ~300 MB/year, well under the 10 GiB per-query limit; [0003](decisions/0003-cost-guardrails.md)):

```bash
cd transform
dbt build --profiles-dir . --target local --full-refresh --select <model>   # in dev_silver first
dbt build --profiles-dir . --target gcp   --full-refresh --select <model>   # then production silver
```

The second command runs with your own credentials against production silver. It rebuilds only that table from bronze, and bronze is never touched. The next scheduled transform carries on incrementally from there.

## Roll back a deploy

Re-run the deploy job for the last good commit (GitHub → Actions → the run → "Re-run jobs"), or revert the commit and push. Artifact Registry keeps the 5 most recent images.

## Check what the project is costing

Cloud Console → Billing → Reports, filtered to project `new-england-grid-analytics`. BigQuery bytes billed per query:

```bash
bq query --use_legacy_sql=false --project_id=new-england-grid-analytics '
SELECT DATE(creation_time) AS day, user_email, COUNT(*) AS queries,
       ROUND(SUM(total_bytes_billed) / POW(1024, 3), 2) AS gib_billed
FROM `region-us-east1`.INFORMATION_SCHEMA.JOBS
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY day, user_email ORDER BY day DESC'
```
