# ══════════════════════════════════════════════════════════════════════════════
# Secret Manager — source credentials
#
# Terraform owns each secret (its existence, replication, and who can read it —
# see iam.tf); the value is added by hand so it never appears in code or state:
#   printf '%s' "<value>" | gcloud secrets versions add <secret> --data-file=-
#
# Created ahead of the jobs that use them, so the values can be added as soon
# as the accounts are approved (docs/runbook.md).
# ══════════════════════════════════════════════════════════════════════════════

locals {
  source_secrets = {
    isone-ws-username = "ISO Express username for the ISO-NE web services API (HTTP basic auth)"
    isone-ws-password = "ISO Express password for the ISO-NE web services API"
    eia-api-key       = "EIA Open Data API key"
  }
}

resource "google_secret_manager_secret" "source" {
  for_each = local.source_secrets

  secret_id = each.key
  annotations = {
    purpose = each.value
  }

  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.api["secret_manager"]]
}
