# ══════════════════════════════════════════════════════════════════════════════
# Cloud Scheduler — cron triggers for the Cloud Run jobs
#
# Each trigger POSTs to the Cloud Run Admin API's jobs.run endpoint as the
# job-scheduler service account, which may run only these jobs (iam.tf).
# Ingest schedules come from local.ingest_jobs (cloud-run-jobs.tf); backfill-only
# jobs have none.
# ══════════════════════════════════════════════════════════════════════════════

locals {
  run_jobs_api = "https://${var.location}-run.googleapis.com/v2/projects/${var.project_id}/locations/${var.location}/jobs"
}

# ── Ingest triggers ───────────────────────────────────────────────────────────

resource "google_cloud_scheduler_job" "ingest" {
  for_each = local.scheduled_ingest_jobs

  name             = "ingest-${each.key}"
  schedule         = each.value.schedule
  time_zone        = var.scheduler_time_zone
  attempt_deadline = "180s"
  paused           = false

  # Retries are handled by the job itself (max_retries), not the trigger
  retry_config {
    retry_count = 0
  }

  http_target {
    http_method = "POST"
    uri         = "${local.run_jobs_api}/${google_cloud_run_v2_job.ingest[each.key].name}:run"
    oauth_token {
      service_account_email = google_service_account.job_scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}

# ── Transform trigger ─────────────────────────────────────────────────────────

resource "google_cloud_scheduler_job" "transform" {
  name             = "transform"
  schedule         = var.transform_schedule
  time_zone        = var.scheduler_time_zone
  attempt_deadline = "600s" # 10 minutes deadline for dbt
  paused           = false

  retry_config {
    retry_count = 1 # Retry once if it fails
  }

  http_target {
    http_method = "POST"
    uri         = "${local.run_jobs_api}/${google_cloud_run_v2_job.transform.name}:run"
    oauth_token {
      service_account_email = google_service_account.job_scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}
