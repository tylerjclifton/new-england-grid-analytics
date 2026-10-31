# 0011 — Bronze schemas are owned by Terraform; silver and gold by dbt

**Status:** Accepted · **Date:** 2026-10-31 (the pattern was carried over from mbta-reliability-analytics; recorded here once asked about)

## Context
A table's definition can live in three places: Terraform, hand-run `CREATE TABLE` scripts, or the ingest code itself (letting the first load create the table). Bronze tables hold the only copy of data sources don't keep ([0001](0001-append-only-bronze.md)), and each one's schema is a contract between an ingest job and the warehouse.

## Decision
- **Bronze tables are defined in Terraform**, in one `bronze_tables` map in `infra/bigquery.tf`: columns, types, descriptions, partitioning, clustering. The same map generates the `dev_bronze` copies ([0008](0008-local-ingest-writes-dev-bronze.md)).
- **Ingest jobs load against the live table's schema** (`ingest/common/load.py`) and never create or alter tables. A missing, misnamed, or mistyped column fails the load, and the failure emails.
- **Silver and gold are owned by dbt**: the SQL that builds a table is its definition, so they never appear in Terraform.
- **No hand-run DDL scripts.** Nothing would record whether one was applied, a console change would go unnoticed, and it wouldn't ship with the code that needs it.

## Consequences
- A new source adds its table to `bronze_tables` in the same push as its ingest job; `terraform plan` shows the table before it exists, and drift shows on any later plan ([0004](0004-terraform-only-changes.md)).
- Adding a column is an in-place update. Changing a type or dropping a column would mean replacing the table, which `prevent_destroy` blocks, so that's a deliberate migration ([0001](0001-append-only-bronze.md)), never a side effect.
- Column descriptions in Terraform are the bronze data dictionary; BigQuery shows them in the console.
