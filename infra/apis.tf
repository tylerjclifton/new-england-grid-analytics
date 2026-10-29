# ══════════════════════════════════════════════════════════════════════════════
# Google APIs the project uses
#
# Only what the pipeline needs. disable_on_destroy = false everywhere: removing
# an entry here stops Terraform managing it but never switches the API off
# underneath a running service.
#
# A new project also starts with Google's default "Google Cloud APIs" bundle
# (Dataplex, Datastore, Analytics Hub, BigQuery Data Transfer, …). Those are
# left as Google enabled them; they cost nothing unused.
# ══════════════════════════════════════════════════════════════════════════════

locals {
  project_apis = {
    # Data
    bigquery         = "bigquery.googleapis.com"        # warehouse (bronze/silver/gold)
    bigquery_storage = "bigquerystorage.googleapis.com" # fast table reads; required by BigQuery

    # Compute + scheduling
    run             = "run.googleapis.com"            # ingest and transform jobs
    cloud_scheduler = "cloudscheduler.googleapis.com" # cron triggers
    cloud_trace     = "cloudtrace.googleapis.com"     # required by Cloud Scheduler

    # Cost guardrail (the budget itself lives on the billing account, outside Terraform)
    billing_budgets = "billingbudgets.googleapis.com"

    # Images + secrets
    artifact_registry = "artifactregistry.googleapis.com" # Docker images
    secret_manager    = "secretmanager.googleapis.com"    # ISO-NE login, EIA API key

    # Storage (Terraform state bucket)
    storage           = "storage.googleapis.com"
    storage_api       = "storage-api.googleapis.com"
    storage_component = "storage-component.googleapis.com"

    # Identity, logging, and platform plumbing
    iam                    = "iam.googleapis.com"
    iam_credentials        = "iamcredentials.googleapis.com" # short-lived tokens (Scheduler → Run, GitHub → deployer)
    sts                    = "sts.googleapis.com"            # exchanges GitHub OIDC tokens (deploy.tf)
    logging                = "logging.googleapis.com"
    monitoring             = "monitoring.googleapis.com"
    cloud_resource_manager = "cloudresourcemanager.googleapis.com"
    service_management     = "servicemanagement.googleapis.com"
    service_usage          = "serviceusage.googleapis.com"
  }
}

resource "google_project_service" "api" {
  for_each = local.project_apis

  service            = each.value
  disable_on_destroy = false
}
