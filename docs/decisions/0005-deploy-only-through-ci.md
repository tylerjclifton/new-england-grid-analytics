# 0005 — Deploy only by pushing to `main`

**Status:** Accepted · **Date:** 2026-10-29 (carried over from mbta-reliability-analytics)

## Context
Local builds and applies drift from what's actually deployed and depend on one laptop's state.

## Decision
- A push to `main` that passes CI does everything: it builds every image tagged with the commit, runs `terraform apply -var image_tag=<commit>`, and runs the transform once (`.github/workflows/ci.yml`).
- GitHub authenticates with Workload Identity Federation, so no keys exist (`infra/deploy.tf`).
- **Bootstrap, once, locally.** CI can't deploy until its identity (the pool, provider, and `github-deployer`) and the state bucket exist, and Terraform creates those. So the first apply runs from a workstation (README, "Terraform state" and "Continuous deployment"). Every apply after it runs in CI. Local `terraform apply` is otherwise only for emergencies.
- `image_tag` has no default on purpose, so a local plan must name the deployed commit.

## Consequences
- Rolling back means redeploying an earlier commit. Artifact Registry keeps the 5 most recent images.
- When a change adds a new source, push the ingest and tables first, seed them, then push the models that read them. Otherwise the post-deploy transform's freshness check fails on empty tables.
