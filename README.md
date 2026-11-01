# New England Electric Grid Analytics

A data engineering and modeling project on the New England electric grid: what it burns, what it costs, how much it carries, and how weather drives all three. It ingests public grid and weather data on a schedule, transforms it through a medallion architecture in BigQuery, and builds toward load and price forecasting.

**Docs:** [setup on a new machine](docs/setup.md) · [runbook](docs/runbook.md) · [decision records](docs/decisions/README.md) · [roadmap](docs/roadmap.md) · [data source notes](docs/data-sources.md)

**Status:** weather, ISO-NE (generation by fuel, load, prices) and EIA-930 (demand, ISO-NE's demand forecast, generation by fuel) are ingesting; history backfills are under way, and the first gold table is next ([roadmap](docs/roadmap.md)).

---

## What It Does

| Source | Data | Schedule | Each run pulls |
|---|---|---|---|
| Open-Meteo forecast API | Hourly weather for one point per ISO-NE load zone: temperature, dew point, cloud cover, solar irradiance, wind at 10 m and 100 m, precipitation, snowfall | Every 6 hours | Yesterday's best estimate plus the 7-day forecast (snapshot; every run kept) |
| ISO-NE web services | Generation by fuel: MW per fuel every few minutes, and which fuel is setting the price | Every 6 hours | Every snapshot for yesterday and today ([0010](docs/decisions/0010-isone-day-files.md)) |
| ISO-NE web services | Five-minute system load, plus ISO-NE's rooftop solar estimate | Every 6 hours | Every interval for yesterday and today |
| ISO-NE web services | Five-minute load per load zone, with each zone's rooftop solar estimate | Every 6 hours | Every interval for yesterday and today |
| ISO-NE web services | Five-minute real-time prices at the Hub and eight load zones (energy, congestion, losses) | Every 6 hours | Preliminary prices for yesterday and today; final prices for 2–3 days ago ([0012](docs/decisions/0012-isone-prices.md)) |
| ISO-NE web services | Hourly day-ahead prices at the Hub and eight load zones | Every 6 hours | Today and tomorrow (tomorrow once the market clears, around midday) |
| EIA-930 API | ISO New England hourly demand, ISO-NE's day-ahead demand forecast, net generation, interchange | Daily | The last 14 days (EIA revises recent hours; [0014](docs/decisions/0014-eia-930.md)) |
| EIA-930 API | ISO New England hourly net generation by fuel | Daily | The last 14 days |
| Open-Meteo archive API | Hourly reanalysis (the best estimate of past weather) for the same points and variables | Daily | The last 14 days through yesterday ([0015](docs/decisions/0015-weather-history.md)) |

The dbt transform runs every 6 hours, after the ingest runs.

---

## Architecture

```
Open-Meteo  ──┐                         ┌─────────────────────────────────────────┐
ISO-NE      ──┼──► Cloud Run Jobs ──►   │  BigQuery                               │
EIA         ──┘         ↑               │  bronze → silver → gold                 │
                 Cloud Scheduler        │            └─ dbt Core ─┘               │
                                        └─────────────────────────────────────────┘
```

Everything is defined in Terraform and deployed by GitHub Actions on every push to `main`. Sources in parentheses are planned.

### Medallion layers

Each layer is its own BigQuery dataset.

| Layer | Stored as | Written by | Role |
|---|---|---|---|
| `bronze` | Append-only tables (Terraform-managed, deletion-protected) | Ingest jobs | Raw history. Each run appends what it saw; rows are never updated or deleted, so revisions and superseded forecasts are kept ([0001](docs/decisions/0001-append-only-bronze.md)) |
| `silver` | Views, or incremental tables over growing bronze | dbt | Every model is `<bronze table>__<step>`: `__base` is each source's cleaned copy (renamed, typed, converted); other steps apply one rule each ([0007](docs/decisions/0007-silver-naming-and-materialization.md)) |
| `gold` | Tables, rebuilt every run | dbt | Cross-source tables for the dashboard and models (none yet) |

| Bronze table | Grain | How bronze grows |
|---|---|---|
| `openmeteo_forecast` | load zone × hour × ingest run | ~1,500 rows per run, ~300 MB/year: every forecast run is kept, so any hour has every forecast made of it ([0009](docs/decisions/0009-weather-per-load-zone.md)) |
| `isone_fuel_mix` | snapshot × fuel × ingest run | ~3,000 rows per run, ~330 MB/year: each run re-pulls yesterday and today, so revisions are kept ([0010](docs/decisions/0010-isone-day-files.md)) |
| `isone_system_load` | five-minute interval × ingest run | ~430 rows per run, ~50 MB/year |
| `isone_zonal_load` | five-minute interval × load zone × ingest run | ~3,500 rows per run, ~400 MB/year |
| `isone_rt_lmp` | five-minute interval × location × version (prelim/final) × ingest run | ~9,900 rows per run, ~1.5 GB/year: the largest table ([0012](docs/decisions/0012-isone-prices.md)) |
| `isone_da_lmp` | hour × location × ingest run | ~440 rows per run, ~65 MB/year |
| `isone_rt_lmp_hourly` | hour × location × ingest run | Backfill only: hourly real-time prices for 2019–2024, before the five-minute history ([0013](docs/decisions/0013-isone-backfill.md)) |
| `eia_region_data` | hour × measure × ingest run | ~1,300 rows per daily run (two weeks re-pulled), ~50 MB/year; history from 2019 ([0014](docs/decisions/0014-eia-930.md)) |
| `eia_fuel_type_data` | hour × fuel × ingest run | ~3,700 rows per daily run, ~115 MB/year; history from 2019 |
| `eia_region_data_bulk` | hour × measure × ingest run | Backfill only: 2015-07 to 2018-12 from EIA's bulk files, in the API's shape |
| `openmeteo_archive` | load zone × hour × ingest run | ~2,700 rows per daily run (two weeks re-pulled); backfilled from 2015-07 ([0015](docs/decisions/0015-weather-history.md)) |
| `openmeteo_previous_runs` | load zone × hour × lead (1–2 days) × ingest run | Backfill only: past forecasts as issued, 2021 to 2026-10-28, for training models on what was known |

| Silver model | Grain | What it produces |
|---|---|---|
| `openmeteo_forecast__base` | load zone × hour × ingest run | Every forecast in grid units (°F, m/s, W/m²), with `lead_hours` from run to hour. A view |
| `openmeteo_forecast__latest` | load zone × hour | The newest value per hour: best estimate for past hours, latest forecast ahead. Incremental table |
| `openmeteo_archive__base` / `__latest` | load zone × hour (× ingest run) | Reanalysis from 2015-07, the weather as it was, in the forecast's units. View / incremental table ([0015](docs/decisions/0015-weather-history.md)) |
| `openmeteo_previous_runs__base` / `__latest` | load zone × hour × lead (× ingest run) | Forecasts as issued 1 and 2 days ahead, 2021 to 2026-10-28: what a day-ahead model may train on. View / incremental table |
| `isone_fuel_mix__base` | snapshot × fuel × ingest run | Every fuel mix snapshot, renamed; fuels not running are absent, not 0. A view |
| `isone_fuel_mix__latest` | snapshot × fuel | The newest version of each snapshot: MW per fuel and which fuel was marginal. Incremental table |
| `isone_system_load__base` | five-minute interval × ingest run | Every load interval, with ISO-NE's rooftop solar estimate as `btm_solar_mw`. A view |
| `isone_system_load__latest` | five-minute interval | The newest version of each interval: measured load and load with rooftop solar added back. Incremental table |
| `isone_zonal_load__base` | five-minute interval × load zone × ingest run | Every zonal load interval, with the zone as its code (ME … NEMA) and its rooftop solar. A view |
| `isone_zonal_load__latest` | five-minute interval × load zone | The newest version of each zone's load, with and without rooftop solar. Incremental table |
| `isone_rt_lmp__base` | five-minute interval × location × version × ingest run | Every real-time price (Hub and zones), with `is_final`. A view |
| `isone_rt_lmp__latest` | five-minute interval × location | The best real-time price: final once published, preliminary until then. Incremental table |
| `isone_da_lmp__base` | hour × location × ingest run | Every day-ahead price (Hub and zones). A view |
| `isone_da_lmp__latest` | hour × location | The day-ahead price per hour and location. Incremental table |
| `isone_rt_lmp_hourly__base` / `__latest` | hour × location (× ingest run) | Hourly real-time prices for 2019–2024, before the five-minute history ([0013](docs/decisions/0013-isone-backfill.md)). View / incremental table |
| `eia_region_data__base` | hour × measure × ingest run | EIA-930 demand, ISO-NE's day-ahead forecast, generation and interchange: the API (2019 on) and bulk files (2015–2018) in one shape, relabelled from hour end to hour start. A view |
| `eia_region_data__latest` | hour × measure | EIA's newest value for each hour and measure, 2015-07 on. Incremental table |
| `eia_region_data__by_hour` | hour | Demand, forecast, generation and interchange side by side. A view |
| `eia_fuel_type_data__base` / `__latest` | hour × fuel (× ingest run) | EIA-930 generation by fuel, 2019 on, by hour start. View / incremental table |
| `isone_pricing_locations` (seed) | location | ISO-NE location ID → project code (HUB, ME … NEMA), kept in `transform/seeds/` |

**Forecast vs. best estimate.** Explaining what happened uses the reanalysis (`openmeteo_archive__latest`, from 2015) or the forecast's `__latest`. A model that predicts ahead must use what was known at the time: `openmeteo_previous_runs__latest` before 2026-10-29, `openmeteo_forecast__base` at the right `lead_hours` after, or it trains on information it won't have when it runs ([0009](docs/decisions/0009-weather-per-load-zone.md), [0015](docs/decisions/0015-weather-history.md)). A day ahead, the forecast's temperature was off by 2.4°F on average (2021–2026).

### Data quality

Tests run inside `dbt build`, before gold is rebuilt; a failing test skips everything downstream. They sit on tables, not on views over all of bronze, so a test never rescans all history ([0003](docs/decisions/0003-cost-guardrails.md)). Unit tests (inline rows → expected rows, `unit_tests:` in the model yml) pin rules a day's real data may not exercise, such as a final price beating a newer preliminary one. Then `dbt source freshness` fails the run if an ingest job has stopped writing (thresholds per source in `transform/models/bronze/_bronze__sources.yml`).

### Alerting

Every Cloud Run job logs one structured failure report when it fails (`ingest/common/run.py`, `transform/run.py`), and a per-job alert policy emails it, with the error or dbt's failure summary (`infra/monitoring.tf`). Only the final attempt alerts, so a blip absorbed by the retry sends nothing, and a lasting failure sends at most one email per job every 6 hours. A backstop emails if the transform hasn't succeeded in 13 hours (timeouts, out-of-memory kills, the scheduler not starting it).

---

## Conventions

| Thing | Convention | Example |
|---|---|---|
| Datasets | Medallion layer | `bronze`, `silver`, `gold` |
| Bronze tables | `<source>_<entity>` | `openmeteo_forecast` |
| Silver models | `<bronze table>__<step>`; `__base` is the cleaned copy | `openmeteo_forecast__base`, `openmeteo_forecast__latest` |
| Gold tables | `<domain>_<entity>` | |
| Seeds | `<source>_<entity>`, small reference data in `transform/seeds/`, loaded into silver | `isone_pricing_locations` |
| Ingest jobs | `ingest/<source>-<entity>/main.py` → `bronze.<source>_<entity>` | `ingest/openmeteo-forecast` → `bronze.openmeteo_forecast` |
| Bronze columns | Source system's names and units, plus audit columns | `temperature_2m`, `GenMw`, `SystemLoadBtmPv` |
| Silver / gold columns | `snake_case`; `_at` = TIMESTAMP (UTC, [0002](docs/decisions/0002-timestamps-in-utc.md)); `_date` = DATE (Eastern); measures carry their unit; booleans `is_` | `hour_at`, `temperature_f`, `wind_speed_100m_ms` |
| Time zones | Stored in UTC; local time derived in silver or gold with `America/New_York` | |
| Load zones | ISO-NE's eight names | `ME`, `NH`, `VT`, `CT`, `RI`, `SEMA`, `WCMA`, `NEMA` |
| Audit columns | On every bronze table, carried into silver and gold | `ingested_at`, `ingested_by` |
| dbt models | Header comment (purpose, grain, numbered steps); CTEs named after the step | `new_runs` |
| Ingest scripts | Docstring (source, cadence, each run, writes to); Fetch → Shape → Write sections | |

---

## Security & Access

Each workload runs as its own service account with access granted per dataset (`infra/iam.tf`). No workload has a project-wide data or admin role.

| Service account | Runs | Access |
|---|---|---|
| `ingest-jobs` | Ingest jobs | Write `bronze`; read the source credential secrets |
| `dbt-bigquery` | Transform job | Read `bronze`; write `silver` and `gold` |
| `job-scheduler` | Cloud Scheduler | Start the Cloud Run jobs (`run.invoker` on each job) |
| `github-deployer` | CI/CD (GitHub Actions) | Build, push, and `terraform apply` — broad by necessity, usable only from this repo's `main` branch |

The data workloads also hold `bigquery.jobUser` (permission to run queries), which grants no data access on its own. Source credentials (the ISO-NE login, the EIA key) live in Secret Manager (`infra/secrets.tf`): Terraform owns the secrets, and the values are added by hand ([runbook](docs/runbook.md)).

---

## Cost

Designed to cost $0–3/month ([0003](docs/decisions/0003-cost-guardrails.md)). The project shares a billing account (and so its free tiers) with mbta-reliability-analytics.

- **Cadence:** every ingest job and the transform run every 6 hours, on 1 vCPU each. ISO-NE jobs pull whole days, so they don't need to poll often to get every interval. Frequency is the main compute cost, so it's raised only when a source needs it.
- **Incremental silver:** models over growing bronze read only new ingest runs, so query cost stays flat as history grows.
- **Per-query limit:** `maximum_bytes_billed` of 10 GiB (~$0.06) on every dbt query (`transform/profiles.yml`). A query that would bill more fails before it runs, and the failure emails.
- **Budget:** $5/month on the billing account, alerting at 50%, 90%, 100%, forecast 100%, 200%, and 400% ($20). Created with `gcloud billing budgets` (setup), outside Terraform, since the deployer has no billing access. It only alerts; there's no billing kill switch, which would stop ingest and lose data sources don't keep.
- **No project-wide daily query quota.** The MBTA project found that one refuses queries far below its limit.

---

## Stack

| Layer | Tool |
|---|---|
| Ingest | Python 3.13 (pandas, requests) on Cloud Run Jobs, triggered by Cloud Scheduler |
| Warehouse | BigQuery (us-east1) |
| Transform | dbt Core 1.12 + dbt-bigquery |
| Infrastructure | Terraform 1.14 (Google provider 7.16), state in GCS |
| CI/CD | GitHub Actions, Workload Identity Federation (no keys) |
| Alerting | Cloud Monitoring log-based alert policies → email |

---

## Project Structure

```
.github/workflows/ci.yml   Checks on every push; deploy on main
docs/                      Setup, runbook, roadmap, data source notes, decision records
infra/                     Terraform: one file per resource family
  bigquery.tf              Datasets and bronze table schemas (the one place they're defined)
  cloud-run-jobs.tf        Ingest jobs (one per source) and the transform
  cloud-scheduler.tf       Cron triggers
  deploy.tf                GitHub → Google identity for CI (Workload Identity Federation)
  monitoring.tf            Failure alert policies
  secrets.tf               Source credentials (values added by hand)
ingest/                    One shared image for every ingest job
  common/run.py            What every run shares: job name, run timestamp, logging, failure reports
  common/fetch.py          fetch(): HTTP GET that retries transient errors (rate limits too), redacts keys, and fails the job cleanly (step 1)
  common/load.py           append_to_bronze(): load into bronze (step 3)
  common/isone.py          ISO-NE API: login, days and pricing locations to pull, response unwrapping
  common/eia.py            EIA API: key, hours to pull, paging, shaping
  common/backfill.py       Backfill mode shared by every job that has one (day range, monthly batches)
  common/openmeteo.py      Open-Meteo: load zone points, variables, request settings, shaping
  openmeteo-forecast/      Open-Meteo hourly forecasts per load zone (every 6 hours)
  openmeteo-archive/       Open-Meteo hourly reanalysis per load zone (daily)
  openmeteo-previous-runs/ Open-Meteo past forecasts, 1–2 days ahead (backfill only)
  isone-fuel-mix/          ISO-NE generation by fuel (every 6 hours)
  isone-system-load/       ISO-NE five-minute system load (every 6 hours)
  isone-zonal-load/        ISO-NE five-minute load per load zone (every 6 hours)
  isone-rt-lmp/            ISO-NE five-minute real-time prices, prelim and final (every 6 hours)
  isone-da-lmp/            ISO-NE hourly day-ahead prices (every 6 hours)
  isone-rt-lmp-hourly/     ISO-NE hourly real-time prices, 2019–2024 (backfill only)
  eia-region-data/         EIA-930 demand, demand forecast, generation, interchange (daily)
  eia-fuel-type-data/      EIA-930 generation by fuel (daily)
  eia-region-data-bulk/    EIA-930 2015–2018 from the bulk files (backfill only)
  tests/                   Job tests against canned API responses
transform/                 dbt Core project
  models/bronze/           Sources and freshness thresholds
  models/silver/           <bronze table>__<step> models
  seeds/                   Reference data (ISO-NE location IDs → load zone codes)
  macros/                  keep_latest_version (optionally preferring final versions), last_processed_run, openmeteo_weather_columns, dataset naming
  run.py                   Transform entrypoint: dbt build, source freshness, failure report
scripts/build-image.sh     Build and push a component image
```

---

## Development & Deployment

CI (`.github/workflows/ci.yml`) runs on every push and pull request without cloud credentials: ruff + pytest for the Python, `dbt parse` + sqlfluff for the SQL, and `terraform fmt` + `validate` for the infrastructure.

```bash
# Local environment (Python 3.13, as in the images; all components + dev tools)
pip install -r requirements.txt

# The same checks CI runs
ruff check ingest transform && pytest                                  # Python
(cd transform && dbt parse --profiles-dir . && sqlfluff lint models)   # SQL
(cd infra && terraform fmt -check -recursive && terraform validate)    # Terraform

# Run an ingest job locally. It writes to dev_bronze (same tables as bronze; rows
# expire after 7 days), never production bronze (decision 0008). To write real
# bronze, run the Cloud Run job instead (docs/runbook.md, "Run a job now").
PYTHONPATH=ingest python ingest/openmeteo-forecast/main.py

# Build/test dbt models locally (uses gcloud application-default credentials).
# The local target reads the real bronze and writes to dev_silver / dev_gold.
cd transform && dbt build --profiles-dir . --target local

# Ship a change: merge to main — CI/CD builds, pushes, applies, and runs the
# transform. To preview infra changes locally, plan against the deployed tag
# (the variables give local credentials a quota project; see docs/setup.md):
cd infra && USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT=new-england-grid-analytics \
  terraform plan -var image_tag=$(git rev-parse --short=12 origin/main)
```

### Continuous deployment

A push to `main` that passes CI deploys automatically (`deploy` job in `.github/workflows/ci.yml`):

1. Build the `ingest` and `transform` images and tag each with the commit (first 12 characters of the SHA)
2. `terraform apply -var image_tag=<commit>` — every job moves to that commit's images
3. Run the transform once, so model changes are live immediately

GitHub authenticates to Google with **Workload Identity Federation**: a short-lived OIDC token exchanged for the `github-deployer` service account, so no keys exist anywhere. Only workflow runs on this repository's `main` branch are accepted (`infra/deploy.tf`). Rolling back is re-running the deploy for an earlier commit; Artifact Registry keeps the 5 most recent images.

The deploy identity can't create itself, so the first apply runs once from a workstation ([0005](docs/decisions/0005-deploy-only-through-ci.md)); every apply after it runs in CI. The steps are in [setup.md](docs/setup.md#bootstrap-once-per-project).

### Terraform state

State lives in the GCS bucket `new-england-grid-analytics-tfstate` (versioned, 30-day history; `infra/cloud-storage.tf`), configured as the backend in `infra/main.tf`. The bucket is itself managed by Terraform, so it's bootstrapped with local state first and then migrated ([setup.md](docs/setup.md#bootstrap-once-per-project)). After that, `terraform init` in `infra/` is all a new machine needs (with `gcloud auth application-default login`).
