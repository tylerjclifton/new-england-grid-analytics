# ══════════════════════════════════════════════════════════════════════════════
# Cloud Storage — the bucket holding Terraform's remote state
#
# Bootstrapped with a local backend, then migrated via
# `terraform init -migrate-state` (see README, Terraform state).
# ══════════════════════════════════════════════════════════════════════════════

resource "google_storage_bucket" "tfstate" {
  name                        = "${var.project_id}-tfstate"
  location                    = var.location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # Keep state history bounded — old versions beyond 30 days are pruned.
  lifecycle_rule {
    condition {
      age        = 30
      with_state = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
