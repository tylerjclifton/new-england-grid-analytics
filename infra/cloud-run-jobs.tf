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

  # One entry per ingest job. Key = job folder under ingest/ = bronze table
  # name with "-" for "_" (e.g. openmeteo-forecast → bronze.openmeteo_forecast).
  #   secrets  env var name → Secret Manager secret (secrets.tf) the job reads
  #   env      plain job-specific settings
  ingest_jobs = {
    "openmeteo-forecast" = {
      schedule = var.weather_forecast_ingestion_schedule
      memory   = "512Mi"
      timeout  = "300s" # One request covering every load zone
      secrets  = {}
      env      = {}
    }
  }
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
