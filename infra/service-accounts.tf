# ══════════════════════════════════════════════════════════════════════════════
# Service accounts — one per workload, each granted only what it uses (iam.tf)
#
# A dashboard account (read gold) joins these when the dashboard is added.
# ══════════════════════════════════════════════════════════════════════════════

# Ingest jobs: append to bronze, read the source credentials
resource "google_service_account" "ingest" {
  account_id   = "ingest-jobs"
  display_name = "Ingest jobs (write bronze)"
}

# Transform job: read bronze, build silver and gold
resource "google_service_account" "dbt_bigquery" {
  account_id   = "dbt-bigquery"
  display_name = "dbt transform (read bronze, write silver/gold)"
}

# Cloud Scheduler: start the Cloud Run jobs on their crons
resource "google_service_account" "job_scheduler" {
  account_id   = "job-scheduler"
  display_name = "Cloud Scheduler (run jobs)"
}
