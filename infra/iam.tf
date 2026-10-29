# ══════════════════════════════════════════════════════════════════════════════
# IAM — least privilege per workload
#
# Data access is granted per dataset, not project-wide. The only project-level
# role a workload gets is bigquery.jobUser (permission to run queries/loads),
# which grants no data access by itself.
#
#                  bronze        silver        gold          other
#   ingest-jobs    dataEditor    —             —             source secrets (secrets.tf)
#   dbt-bigquery   dataViewer    dataEditor    dataEditor    bigquery.user (dataset lookups)
#   job-scheduler  —             —             —             run.invoker on each job
#   github-deployer  deploys via terraform; broad by necessity (deploy.tf)
# ══════════════════════════════════════════════════════════════════════════════

# ── Project-level ─────────────────────────────────────────────────────────────

locals {
  project_roles = {
    ingest_job_user = { member = google_service_account.ingest.member, role = "roles/bigquery.jobUser" }
    dbt_job_user    = { member = google_service_account.dbt_bigquery.member, role = "roles/bigquery.jobUser" }
    # dbt lists and looks up datasets before building; bigquery.user covers that
    # without granting read or write on any existing dataset
    dbt_user = { member = google_service_account.dbt_bigquery.member, role = "roles/bigquery.user" }
  }
}

resource "google_project_iam_member" "workload" {
  for_each = local.project_roles

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

# ── Dataset-level ─────────────────────────────────────────────────────────────

locals {
  dataset_roles = {
    ingest_writes_bronze = { dataset = google_bigquery_dataset.bronze.dataset_id, role = "roles/bigquery.dataEditor", member = google_service_account.ingest.member }
    dbt_reads_bronze     = { dataset = google_bigquery_dataset.bronze.dataset_id, role = "roles/bigquery.dataViewer", member = google_service_account.dbt_bigquery.member }
    dbt_writes_silver    = { dataset = google_bigquery_dataset.silver.dataset_id, role = "roles/bigquery.dataEditor", member = google_service_account.dbt_bigquery.member }
    dbt_writes_gold      = { dataset = google_bigquery_dataset.gold.dataset_id, role = "roles/bigquery.dataEditor", member = google_service_account.dbt_bigquery.member }
  }
}

resource "google_bigquery_dataset_iam_member" "workload" {
  for_each = local.dataset_roles

  dataset_id = each.value.dataset
  role       = each.value.role
  member     = each.value.member
}

# ── Secret and job-level ──────────────────────────────────────────────────────

# Ingest jobs read the source credentials (secrets.tf)
resource "google_secret_manager_secret_iam_member" "ingest_reads_source_secrets" {
  for_each = google_secret_manager_secret.source

  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.ingest.member
}

# The scheduler may start exactly these jobs (run.invoker includes run.jobs.run)
resource "google_cloud_run_v2_job_iam_member" "scheduler_runs_ingest" {
  for_each = google_cloud_run_v2_job.ingest

  name     = each.value.name
  location = each.value.location
  role     = "roles/run.invoker"
  member   = google_service_account.job_scheduler.member
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_runs_transform" {
  name     = google_cloud_run_v2_job.transform.name
  location = google_cloud_run_v2_job.transform.location
  role     = "roles/run.invoker"
  member   = google_service_account.job_scheduler.member
}

# ── Google service agents ─────────────────────────────────────────────────────
# Google grants these when an API is enabled; they're kept here so Terraform
# documents (and would restore) them. Removing one breaks its service.

locals {
  service_agent_roles = {
    cloud_run         = { member = "serviceAccount:${var.default_sa_cloud_run}", role = "roles/run.serviceAgent" }
    artifact_registry = { member = "serviceAccount:${var.default_sa_artifact_registry}", role = "roles/artifactregistry.serviceAgent" }
    cloud_scheduler   = { member = "serviceAccount:${var.default_sa_cloud_scheduler}", role = "roles/cloudscheduler.serviceAgent" }
    # Google APIs service agent: Editor is Google's default for project-level
    # automation (e.g. creating managed resources); not used by our workloads
    google_apis = { member = "serviceAccount:${var.default_sa_google_apis}", role = "roles/editor" }
  }
}

resource "google_project_iam_member" "service_agent" {
  for_each = local.service_agent_roles

  project = var.project_id
  role    = each.value.role
  member  = each.value.member

  # The agents exist only once their APIs are enabled
  depends_on = [google_project_service.api]
}
