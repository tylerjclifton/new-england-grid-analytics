# CLAUDE.md

Guidance for AI coding sessions in this repo. Humans: the same docs apply.

**Read first:** [README.md](README.md) (architecture, conventions, cost), [docs/decisions/](docs/decisions/README.md) (why things are the way they are), [docs/roadmap.md](docs/roadmap.md) (what's planned), [docs/data-sources.md](docs/data-sources.md) (what each source offers), [docs/setup.md](docs/setup.md), and [docs/runbook.md](docs/runbook.md).

## Rules
- **Bronze is append-only.** Never update, delete, or rebuild bronze rows or tables ([0001](docs/decisions/0001-append-only-bronze.md)).
- **Timestamps are UTC** in storage; local time is derived ([0002](docs/decisions/0002-timestamps-in-utc.md)).
- **Mind the cost** ([0003](docs/decisions/0003-cost-guardrails.md)): a few dollars a month is fine, $50 is a red flag. Before adding a source or raising a schedule, estimate bronze growth and query cost. Models over growing bronze are incremental; tests go on tables, not views over all of bronze.
- **Infrastructure changes go through Terraform only**: edit `infra/`, plan locally, push ([0004](docs/decisions/0004-terraform-only-changes.md)).
- **Deploy by pushing to `main`**; CI builds, applies, and runs the transform ([0005](docs/decisions/0005-deploy-only-through-ci.md)). Watch the run and confirm it passed.
- **Adding a source:** push the ingest and tables first, seed them, then push the models that read them, so the post-deploy freshness check doesn't fail on empty tables.
- **Docs change with the code**, in the same commit: README, dbt model headers and yml, `docs/`. Record new decisions in `docs/decisions/`.
- **Commits carry no AI co-author trailer** or "Generated with" line.
- **Comment generously**: every model and script gets a header with its purpose, grain, and steps; follow the naming conventions in the README.

## Local environment
- Python 3.13 (the system `python3` on macOS is 3.9 and too old). Without it, run checks in `python:3.13-slim` via Docker ([setup](docs/setup.md)).
- This is GCP project `new-england-grid-analytics` (its own project, never mbta-reliability-analytics). Use the `grid` gcloud configuration.
- Local `terraform plan`: `USER_PROJECT_OVERRIDE=true GOOGLE_BILLING_PROJECT=new-england-grid-analytics terraform plan -var image_tag=$(git rev-parse --short=12 origin/main)`.
- Local dbt (`--target local`) writes only to `dev_silver` / `dev_gold`. Test model changes there against live bronze before pushing.
- Local ingest runs write only to `dev_bronze` ([0008](docs/decisions/0008-local-ingest-writes-dev-bronze.md)).
