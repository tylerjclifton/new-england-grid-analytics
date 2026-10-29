# ══════════════════════════════════════════════════════════════════════════════
# Variables — project, deployment, schedules, alerting, and Google service agents
#
# Everything has a default except image_tag, which CI/CD sets on every deploy.
# ══════════════════════════════════════════════════════════════════════════════

# ── Project ───────────────────────────────────────────────────────────────────

variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "new-england-grid-analytics"
}

variable "location" {
  description = "Region for every regional resource"
  type        = string
  default     = "us-east1"
}

# ── Deployment ────────────────────────────────────────────────────────────────

variable "image_tag" {
  description = <<-EOT
    Tag of the ingest and transform images to deploy. CI/CD sets it to the
    commit being deployed (.github/workflows/ci.yml). No default on purpose:
    a local plan must name the deployed tag, e.g.
      terraform plan -var image_tag=$(git rev-parse --short=12 origin/main)
  EOT
  type        = string
}

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to deploy via Workload Identity Federation"
  type        = string
  default     = "tylerjclifton/new-england-grid-analytics"
}

# ── Schedules ─────────────────────────────────────────────────────────────────
# Cadence is a cost decision (decision 0003): a run every 6 hours captures each
# major weather model update, and the transform only needs to follow it.

variable "scheduler_time_zone" {
  description = "Cloud Scheduler time zone for cron jobs"
  type        = string
  default     = "America/New_York"
}

variable "weather_forecast_ingestion_schedule" {
  description = "Cron for Open-Meteo forecast ingestion. Every 6 hours at :05; each run snapshots the next 7 days' hourly forecast (and yesterday's best estimate) for every load zone."
  type        = string
  default     = "5 */6 * * *"
}

variable "transform_schedule" {
  description = "Cron for the dbt transform job. Every 6 hours at :20, just after the weather snapshot."
  type        = string
  default     = "20 */6 * * *"
}

# ── Alerting ──────────────────────────────────────────────────────────────────

variable "alert_email" {
  description = "Address that receives pipeline failure alerts (monitoring.tf)"
  type        = string
  default     = "tylerjclifton@outlook.com"
}

# ── Google service agents ─────────────────────────────────────────────────────
# Project-number-specific (987931704118); granted by Google, documented in iam.tf

variable "default_sa_artifact_registry" {
  description = "Artifact Registry Service Agent"
  type        = string
  default     = "service-987931704118@gcp-sa-artifactregistry.iam.gserviceaccount.com"
}

variable "default_sa_cloud_scheduler" {
  description = "Cloud Scheduler Service Agent"
  type        = string
  default     = "service-987931704118@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}

variable "default_sa_cloud_run" {
  description = "Cloud Run Service Agent"
  type        = string
  default     = "service-987931704118@serverless-robot-prod.iam.gserviceaccount.com"
}
