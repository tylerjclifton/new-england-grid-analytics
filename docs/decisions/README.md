# Decision records

One short file per decision that shaped this project: the situation, what was decided, and what follows from it. They answer "why is it like this?" when the code alone can't.

| # | Decision | Status |
|---|---|---|
| [0001](0001-append-only-bronze.md) | Bronze is append-only; never rely on a source keeping history | Accepted |
| [0002](0002-timestamps-in-utc.md) | Timestamps are stored in UTC | Accepted |
| [0003](0003-cost-guardrails.md) | Cost guardrails from day one: cadence, incremental models, per-query limits, budget alerts | Accepted |
| [0004](0004-terraform-only-changes.md) | Every infrastructure change goes through Terraform | Accepted |
| [0005](0005-deploy-only-through-ci.md) | Deploy only by pushing to `main` (after a one-time local bootstrap) | Accepted |
| [0006](0006-runtime-versions.md) | dbt 1.12 and Python 3.13; dbt v2 skipped for now | Accepted |
| [0007](0007-silver-naming-and-materialization.md) | Silver models are `<bronze table>__<step>`; views unless they sit on growing bronze | Accepted |
| [0008](0008-local-ingest-writes-dev-bronze.md) | Local ingest runs write to `dev_bronze`, never production bronze | Accepted |
| [0009](0009-weather-per-load-zone.md) | Weather: Open-Meteo forecasts, one point per load zone, every run kept | Accepted |
| [0010](0010-isone-day-files.md) | ISO-NE: whole-day pulls (yesterday and today) every 6 hours; source field names in bronze | Accepted |
| [0011](0011-bronze-schemas-in-terraform.md) | Bronze schemas are owned by Terraform; silver and gold by dbt | Accepted |
| [0012](0012-isone-prices.md) | ISO-NE prices: five-minute real-time (preliminary, then final) and hourly day-ahead, at the Hub and eight load zones | Accepted |
| [0013](0013-isone-backfill.md) | ISO-NE backfill: the scheduled jobs run once over a day range; hourly real-time prices before 2024 | Accepted |

**Adding one:** copy the shape of an existing file, take the next number, add a row here.

**Changing one:** refinements made while a decision is still being carried out are added to the record itself, dated, so it tells the whole story. Reversing a decision later gets a new record, and the old one is marked "Superseded by 00NN".
