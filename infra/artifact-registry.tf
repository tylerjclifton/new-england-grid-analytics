# ══════════════════════════════════════════════════════════════════════════════
# Artifact Registry — Docker images for the jobs (ingest, transform)
#
# Cleanup: keep the 5 most recent versions of each image and delete anything
# older than 30 days beyond those. Deployed images are always among the most
# recent, so a rollback target stays available while old builds stop
# accumulating storage (the free tier is 0.5 GB).
#
# A frontend repository joins this one when the dashboard is added.
# ══════════════════════════════════════════════════════════════════════════════

locals {
  image_repositories = {
    backend = "Grid backend Docker images (ingest, transform)"
  }
}

resource "google_artifact_registry_repository" "repo" {
  for_each = local.image_repositories

  location      = var.location
  repository_id = each.key
  format        = "DOCKER"
  description   = each.value

  cleanup_policy_dry_run = false

  # Policies are evaluated together: KEEP wins over DELETE
  cleanup_policies {
    id     = "keep-5-most-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }
  cleanup_policies {
    id     = "delete-older-than-30-days"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "2592000s" # 30 days
    }
  }
}
