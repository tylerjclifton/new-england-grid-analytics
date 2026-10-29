# ══════════════════════════════════════════════════════════════════════════════
# Terraform settings — Google provider (pinned) and remote state
#
# State lives in the GCS bucket defined in cloud-storage.tf (see README,
# Terraform state). Backend blocks can't read variables, so the bucket name is
# written out here.
# ══════════════════════════════════════════════════════════════════════════════

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.16.0"
    }
  }

  backend "gcs" {
    bucket = "new-england-grid-analytics-tfstate"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.location
}
