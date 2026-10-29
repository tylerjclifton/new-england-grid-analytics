# ══════════════════════════════════════════════════════════════════════════════
# Monitoring — email alerts when the pipeline fails (and only then)
#
#   <job> failed           one policy per Cloud Run job; emails the job's own
#                          failure report (error + traceback or dbt summary)
#   transform not running  backstop for failures a job can't report itself:
#                          timeouts, out-of-memory kills, the scheduler not
#                          starting it. An ingest job failing that way is
#                          caught by the transform's freshness check instead.
#
# Failure report contract (ingest/common/run.py, transform/run.py): a failed
# run prints one JSON line to stdout, which Cloud Run logs as structured data:
#   {"severity": "ERROR", "event": "job_failed", "job": "<job>", "message": "<summary>\n\n<details>"}
# Only a task's final attempt reports job_failed; an attempt Cloud Run will
# retry reports attempt_failed (WARNING), so retried blips send no email.
# ══════════════════════════════════════════════════════════════════════════════

locals {
  # Every Cloud Run job, by name (ingest-openmeteo-forecast, …, transform)
  pipeline_jobs = toset(concat(
    [for job in google_cloud_run_v2_job.ingest : job.name],
    [google_cloud_run_v2_job.transform.name],
  ))
}

resource "google_monitoring_notification_channel" "email" {
  display_name = "Pipeline alerts"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

# ── Job failure reports ───────────────────────────────────────────────────────

resource "google_monitoring_alert_policy" "job_failed" {
  for_each = local.pipeline_jobs

  display_name = "${each.key} failed"
  combiner     = "OR"

  conditions {
    display_name = "${each.key} logged a failure report"
    condition_matched_log {
      filter = <<-EOT
        resource.type="cloud_run_job"
        resource.labels.job_name="${each.key}"
        jsonPayload.event="job_failed"
      EOT
      # Copied from the log entry into the email (documentation below)
      label_extractors = {
        error     = "EXTRACT(jsonPayload.message)"
        execution = "EXTRACT(labels.\"run.googleapis.com/execution_name\")"
      }
    }
  }

  alert_strategy {
    # At most one email per job every 6 hours while it keeps failing, so a
    # lasting outage on a frequent job doesn't send dozens
    notification_rate_limit {
      period = "21600s"
    }
    # Close the alert 30 minutes (the minimum) after the last failure
    auto_close = "1800s"
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  documentation {
    subject   = "${each.key} failed"
    mime_type = "text/markdown"
    content   = <<-EOT
      **${each.key}** failed (execution $${log.extracted_label.execution}). Its error report:

      ```
      $${log.extracted_label.error}
      ```

      Executions and full logs: https://console.cloud.google.com/run/jobs/details/${var.location}/${each.key}/executions?project=${var.project_id}

      While it keeps failing you'll get at most one email every 6 hours.
    EOT
  }
}

# ── Backstop: transform not succeeding ────────────────────────────────────────

resource "google_monitoring_alert_policy" "transform_not_succeeding" {
  display_name = "transform hasn't succeeded in 13 hours"
  combiner     = "OR"

  conditions {
    display_name = "No successful transform execution for 13 hours"
    condition_absent {
      filter   = <<-EOT
        resource.type = "cloud_run_job"
        AND resource.labels.job_name = "${google_cloud_run_v2_job.transform.name}"
        AND metric.type = "run.googleapis.com/job/completed_execution_count"
        AND metric.labels.result = "succeeded"
      EOT
      duration = "46800s" # two missed 6-hourly runs, plus an hour of slack
      aggregations {
        alignment_period   = "3600s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  documentation {
    subject   = "transform hasn't succeeded in 13 hours"
    mime_type = "text/markdown"
    content   = <<-EOT
      The transform (every 6 hours) hasn't completed successfully in 13 hours, so silver and gold are going stale.

      If you also got a **transform failed** email, it has the cause. If not, the job never got to report one: it timed out, ran out of memory, or wasn't started by Cloud Scheduler.

      Executions and full logs: https://console.cloud.google.com/run/jobs/details/${var.location}/${google_cloud_run_v2_job.transform.name}/executions?project=${var.project_id}
    EOT
  }
}
