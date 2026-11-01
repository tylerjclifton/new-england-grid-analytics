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
# major weather model update; ISO-NE runs pull whole days, so they lose nothing
# by running as rarely (decision 0010); the transform only needs to follow them.

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

variable "isone_ingestion_schedule" {
  description = "Cron for the ISO-NE ingest jobs (fuel mix, load, prices). Every 6 hours at :10; each run pulls whole days, so the cadence sets latency, not completeness (decisions 0010, 0012)."
  type        = string
  default     = "10 */6 * * *"
}

variable "eia_ingestion_schedule" {
  description = "Cron for the EIA ingest jobs (region data, fuel type data). Daily at 05:15, before the 06:20 transform; each run re-pulls two weeks, since EIA revises recent hours (decision 0014)."
  type        = string
  default     = "15 5 * * *"
}

variable "transform_schedule" {
  description = "Cron for the dbt transform job. Every 6 hours at :20, just after the weather and ISO-NE runs."
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
