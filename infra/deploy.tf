# ══════════════════════════════════════════════════════════════════════════════
# Continuous deployment — GitHub Actions → Google Cloud, keyless
#
# GitHub Actions proves who it is with a short-lived OIDC token; Workload
# Identity Federation exchanges that for credentials of the github-deployer
# service account. No service account keys exist anywhere. Only workflow runs
# on this repository's main branch are accepted (attribute_condition below).
#
# The deployer runs `terraform apply`, and Terraform manages IAM, so its roles
# are necessarily broad — the branch + repository restriction is what keeps
# them safe. The workflow is .github/workflows/ci.yml (job: deploy).
# ══════════════════════════════════════════════════════════════════════════════

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "Identities from GitHub Actions OIDC tokens"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  # Claims from GitHub's token that IAM can match on
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Reject every token except this repository's main branch
  attribute_condition = "assertion.repository == '${var.github_repository}' && assertion.ref == 'refs/heads/main'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Deploy identity used by GitHub Actions
resource "google_service_account" "github_deployer" {
  account_id   = "github-deployer"
  display_name = "GitHub Actions deployer (build, push, terraform apply)"
}

# Let workflows from the repository impersonate the deployer
resource "google_service_account_iam_member" "github_deployer_wif" {
  service_account_id = google_service_account.github_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# What `terraform apply` touches, one role per resource family it manages
locals {
  deployer_roles = [
    "roles/artifactregistry.admin",               # image repositories + pushing images
    "roles/bigquery.admin",                       # datasets, bronze tables, dataset IAM
    "roles/cloudscheduler.admin",                 # cron triggers
    "roles/iam.serviceAccountAdmin",              # workload service accounts
    "roles/iam.serviceAccountUser",               # attach service accounts to jobs/schedules
    "roles/iam.workloadIdentityPoolAdmin",        # this file's pool and provider
    "roles/logging.configWriter",                 # log-match rules behind the failure alerts
    "roles/monitoring.alertPolicyEditor",         # failure alerting policies (monitoring.tf)
    "roles/monitoring.notificationChannelEditor", # the alert email channel
    "roles/resourcemanager.projectIamAdmin",      # project-level grants (iam.tf)
    "roles/run.admin",                            # jobs and job IAM
    "roles/secretmanager.admin",                  # the source credential secrets and their IAM
    "roles/serviceusage.serviceUsageAdmin",       # enabled APIs (apis.tf)
  ]
}

resource "google_project_iam_member" "github_deployer" {
  for_each = toset(local.deployer_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.github_deployer.member
}

# Terraform state and the state bucket's own settings
resource "google_storage_bucket_iam_member" "github_deployer_tfstate" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.admin"
  member = google_service_account.github_deployer.member
}
