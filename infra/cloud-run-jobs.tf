# ══════════════════════════════════════════════════════════════════════════════
# Cloud Run jobs — ingest (one per source) and transform (dbt)
#
# All ingest jobs run the same image (ingest/Dockerfile); each job runs its own
# script via container args and appends to its bronze table of the same name.
# ══════════════════════════════════════════════════════════════════════════════

locals {
  backend_registry = "${var.location}-docker.pkg.dev/${var.project_id}/backend"

  # Retries per failed task. Each job also receives its value as MAX_RETRIES, so
  # only the final attempt's failure report triggers an alert (monitoring.tf).
  #   ingest     one retry absorbs transient API errors
  #   transform  none: dbt retries BigQuery errors itself, and a failed test or
  #              freshness check won't pass on retry
  ingest_max_retries    = 1
  transform_max_retries = 0

  # Settings every ingest job shares, unless its entry below overrides them:
  #   memory   512 MiB: a job holds at most a month of one feed (backfills
  #            batch by month, decision 0013)
  #   timeout  per scheduled run: 15 minutes, which covers fetch()'s ~8
  #            minutes of retries if a source is rate-limiting or down; a
  #            backfill execution sets its own (--task-timeout, docs/runbook.md)
  #   secrets  env var name → Secret Manager secret (secrets.tf) the job reads
  #   env      plain job-specific settings
  ingest_job_defaults = {
    memory  = "512Mi"
    timeout = "900s"
    secrets = {}
    env     = {}
  }

  # The credentials the jobs read (ingest/common/isone.py, ingest/common/eia.py)
  isone_login = {
    ISONE_WS_USERNAME = "isone-ws-username"
    ISONE_WS_PASSWORD = "isone-ws-password"
  }
  eia_key = { EIA_API_KEY = "eia-api-key" }

  # One entry per ingest job: its schedule (cron, or null for a backfill-only
  # job run by hand, decision 0013) and anything it doesn't share with the
  # defaults. Key = job folder under ingest/ = bronze table name with "-" for
  # "_" (e.g. openmeteo-forecast → bronze.openmeteo_forecast).
  ingest_job_settings = {
    # One request covering every load zone
    "openmeteo-forecast" = { schedule = var.weather_forecast_ingestion_schedule }
    # One request: two weeks, every load zone
    "openmeteo-archive" = { schedule = var.weather_archive_ingestion_schedule }
    # Backfill only: past forecasts before 2026-10-29
    "openmeteo-previous-runs" = { schedule = null }

    # One request per day (yesterday and today)
    "isone-fuel-mix"    = { schedule = var.isone_ingestion_schedule, secrets = local.isone_login }
    "isone-system-load" = { schedule = var.isone_ingestion_schedule, secrets = local.isone_login }
    "isone-zonal-load"  = { schedule = var.isone_ingestion_schedule, secrets = local.isone_login }
    # 36 requests (2 versions × 2 days × 9 locations), ~10 s
    "isone-rt-lmp" = { schedule = var.isone_ingestion_schedule, secrets = local.isone_login }
    # 2 requests: all-locations files for today and tomorrow
    "isone-da-lmp" = { schedule = var.isone_ingestion_schedule, secrets = local.isone_login }
    # 2 requests each: yesterday and tomorrow, every version
    "isone-load-forecast"       = { schedule = var.isone_ingestion_schedule, secrets = local.isone_login }
    "isone-zonal-load-forecast" = { schedule = var.isone_ingestion_schedule, secrets = local.isone_login }
    # 2 requests: yesterday's and today's publications
    "isone-wind-forecast" = { schedule = var.isone_ingestion_schedule, secrets = local.isone_login }
    # Backfill only: hourly prices from before the five-minute history
    "isone-rt-lmp-hourly" = { schedule = null, secrets = local.isone_login }

    # One page each: two weeks × 4 measures, two weeks × ~11 fuels
    "eia-region-data"    = { schedule = var.eia_ingestion_schedule, secrets = local.eia_key }
    "eia-fuel-type-data" = { schedule = var.eia_ingestion_schedule, secrets = local.eia_key }
    # Two requests: Henry Hub daily, the states' power plant gas price monthly
    "eia-natural-gas-prices" = { schedule = var.eia_ingestion_schedule, secrets = local.eia_key }
    # Backfill only: 2015–2018 from the bulk files (no key), ~45 MB of CSV each
    "eia-region-data-bulk" = { schedule = null, memory = "1Gi" }

    # Backfill only: yearly files (no key), ~1.4 GB each, read as they download
    "eaglei-outages" = { schedule = null, memory = "1Gi" }
  }

  # Every ingest job's full settings: the defaults, overridden by its entry
  ingest_jobs = { for job, settings in local.ingest_job_settings : job => merge(local.ingest_job_defaults, settings) }

  # The jobs Cloud Scheduler triggers (cloud-scheduler.tf, iam.tf)
  scheduled_ingest_jobs = { for job, config in local.ingest_jobs : job => config if config.schedule != null }
}

# ── Ingest jobs ───────────────────────────────────────────────────────────────

resource "google_cloud_run_v2_job" "ingest" {
  for_each = local.ingest_jobs

  name     = "ingest-${each.key}"
  location = var.location

  deletion_protection = true

  # Cloud Run checks secret access when the job is updated, so the ingest
  # account's grants on the source secrets must exist first
  depends_on = [google_secret_manager_secret_iam_member.ingest_reads_source_secrets]

  template {
    task_count  = 1 # Total number of tasks to run
    parallelism = 0 # Maximum number of tasks to run concurrently
    template {
      service_account = google_service_account.ingest.email
      timeout         = each.value.timeout
      max_retries     = local.ingest_max_retries

      containers {
        name  = "ingest-${each.key}"
        image = "${local.backend_registry}/ingest:${var.image_tag}"
        args  = ["${each.key}/main.py"]

        env {
          name  = "MAX_RETRIES"
          value = tostring(local.ingest_max_retries)
        }
        env {
          name  = "BQ_PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "BQ_DATASET_ID"
          value = google_bigquery_dataset.bronze.dataset_id
        }
        env {
          name  = "BQ_TABLE_ID"
          value = google_bigquery_table.bronze[replace(each.key, "-", "_")].table_id
        }

        # Job-specific settings
        dynamic "env" {
          for_each = each.value.env
          content {
            name  = env.key
            value = env.value
          }
        }

        # Source credentials, read from Secret Manager at startup
        dynamic "env" {
          for_each = each.value.secrets
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = google_secret_manager_secret.source[env.value].secret_id
                version = "latest"
              }
            }
          }
        }

        resources {
          limits = {
            memory = each.value.memory
            cpu    = "1000m"
          }
        }
      }
    }
  }
}

# ── Transform job ─────────────────────────────────────────────────────────────

resource "google_cloud_run_v2_job" "transform" {
  name     = "transform"
  location = var.location

  deletion_protection = true

  template {
    task_count  = 1 # Total number of tasks to run
    parallelism = 0 # Maximum number of tasks to run concurrently
    template {
      service_account = google_service_account.dbt_bigquery.email
      timeout         = "600s" # 10 minutes for dbt to complete
      max_retries     = local.transform_max_retries
      containers {
        name  = "transform"
        image = "${local.backend_registry}/transform:${var.image_tag}"
        env {
          name  = "MAX_RETRIES"
          value = tostring(local.transform_max_retries)
        }
        env {
          name  = "DBT_PROJECT_ID"
          value = var.project_id
        }
        # One vCPU: dbt mostly waits on BigQuery, so a second one would double
        # the compute bill without making the run meaningfully faster (decision 0003)
        resources {
          limits = {
            memory = "1Gi"
            cpu    = "1000m"
          }
        }
      }
    }
  }
}
