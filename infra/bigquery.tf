# ══════════════════════════════════════════════════════════════════════════════
# BigQuery — medallion datasets and bronze tables
#
#   bronze  Append-only raw history, written directly by ingest jobs. Rows are
#           only ever added, never updated or deleted, so nothing depends on a
#           source keeping its own history (decision 0001). Tables are defined
#           here (not by dbt) so their schemas are owned in one place; ingest
#           jobs load against the live table schema.
#   silver  dbt models: each source's cleaned copy plus steps built on it
#           (decision 0007).
#   gold    dbt tables for the dashboard and models, rebuilt every transform run.
#
# Dev sandboxes mirror the layers for local work, so nothing local touches the
# live datasets: dev_bronze (local ingest runs, ingest/common/load.py), and
# dev_silver / dev_gold (local dbt builds, which read the real bronze).
#
# Naming: tables are `<source>_<entity>`; silver's models built from each are
# `<source>_<entity>__<step>` (`__base` is the cleaned copy); the dataset says
# which layer. Columns ending `_at` are TIMESTAMPs in UTC (decision 0002).
# Every bronze table ends with the same two audit columns.
# ══════════════════════════════════════════════════════════════════════════════

locals {
  # Audit columns appended to every bronze table by ingest/common/load.py
  bronze_audit_columns = [
    { name = "ingested_at", type = "TIMESTAMP", description = "When the ingest run started (UTC); shared by every row written in that run" },
    { name = "ingested_by", type = "STRING", description = "Cloud Run job that wrote the row" },
  ]

  # How long local test data lives in the dev sandboxes
  dev_retention_ms = 7 * 24 * 60 * 60 * 1000

  # One entry per bronze table. Column names follow the source system; renaming
  # to project conventions happens in silver.
  bronze_tables = {
    openmeteo_forecast = {
      description = "Open-Meteo hourly weather forecasts, one point per ISO-NE load zone (decision 0009), in source units. Every run's forecast is kept: the hours ahead are what was predicted at ingested_at, the past day is the model's best estimate. Grain: load zone × hour × ingest run."
      clustering  = ["load_zone", "time"]
      columns = [
        { name = "load_zone", type = "STRING", description = "ISO-NE load zone the point represents (ME, NH, VT, CT, RI, SEMA, WCMA, NEMA); set by the ingest, not the API" },
        { name = "location_name", type = "STRING", description = "City the point is placed at (e.g. Boston); set by the ingest" },
        { name = "latitude", type = "FLOAT", description = "Grid-cell latitude Open-Meteo answered for (snapped from the requested point)" },
        { name = "longitude", type = "FLOAT", description = "Grid-cell longitude Open-Meteo answered for" },
        { name = "elevation", type = "FLOAT", description = "Grid-cell elevation, m" },
        { name = "time", type = "TIMESTAMP", description = "Hour the values are for (UTC). Instantaneous values are at this time; precipitation, snowfall, and radiation cover the hour ending at it" },
        { name = "temperature_2m", type = "FLOAT", description = "Air temperature at 2 m, °C" },
        { name = "dew_point_2m", type = "FLOAT", description = "Dew point at 2 m, °C" },
        { name = "cloud_cover", type = "FLOAT", description = "Total cloud cover, %" },
        { name = "shortwave_radiation", type = "FLOAT", description = "Global horizontal irradiance, W/m², mean over the preceding hour (drives solar output)" },
        { name = "wind_speed_10m", type = "FLOAT", description = "Wind speed at 10 m, m/s" },
        { name = "wind_speed_100m", type = "FLOAT", description = "Wind speed at 100 m (turbine hub height), m/s" },
        { name = "precipitation", type = "FLOAT", description = "Total precipitation (rain + melted snow), mm, preceding hour" },
        { name = "snowfall", type = "FLOAT", description = "Snowfall, cm, preceding hour" },
      ]
    }

    isone_fuel_mix = {
      description = "ISO-NE generation by fuel (decision 0010): snapshots published every few minutes at irregular times, each listing MW per fuel running at that moment. A fuel not running is absent from a snapshot, not 0. Each run re-pulls yesterday and today, so a snapshot appears once per run that saw it. Grain: snapshot × fuel × ingest run."
      clustering  = ["FuelCategory", "BeginDate"]
      columns = [
        { name = "BeginDate", type = "TIMESTAMP", description = "When the snapshot was taken (UTC; ISO-NE sends Eastern time with its offset)" },
        { name = "FuelCategory", type = "STRING", description = "Fuel, e.g. Natural Gas, Nuclear, Hydro, Wind, Solar, Oil, Wood, Refuse, Landfill Gas, Batteries, Other" },
        { name = "FuelCategoryRollup", type = "STRING", description = "ISO-NE's grouping of FuelCategory (Wind, Solar, Wood, Refuse and Landfill Gas roll up to Renewables)" },
        { name = "GenMw", type = "FLOAT", description = "Generation from this fuel at BeginDate, MW" },
        { name = "MarginalFlag", type = "STRING", description = "Y if this fuel was marginal (setting the real-time price) at BeginDate, else N" },
      ]
    }

    isone_system_load = {
      description = "ISO-NE five-minute system load (decision 0010), with ISO-NE's estimate of behind-the-meter (rooftop) solar, which the grid never sees. Each run re-pulls yesterday and today, so an interval appears once per run that saw it. Grain: five-minute interval × ingest run."
      clustering  = ["BeginDate"]
      columns = [
        { name = "BeginDate", type = "TIMESTAMP", description = "Start of the five-minute interval (UTC; ISO-NE sends Eastern time with its offset)" },
        { name = "LoadMw", type = "FLOAT", description = "ISO-NE system load, MW: everything the grid serves" },
        { name = "NativeLoad", type = "FLOAT", description = "LoadMw less ArdDemand, MW" },
        { name = "ArdDemand", type = "FLOAT", description = "Asset-related demand, MW: pumped storage pumping and batteries charging" },
        { name = "SystemLoadBtmPv", type = "FLOAT", description = "LoadMw plus ISO-NE's behind-the-meter solar estimate, MW (equal to LoadMw after dark)" },
        { name = "NativeLoadBtmPv", type = "FLOAT", description = "NativeLoad plus ISO-NE's behind-the-meter solar estimate, MW" },
      ]
    }
  }
}

# ── Datasets ──────────────────────────────────────────────────────────────────

resource "google_bigquery_dataset" "bronze" {
  dataset_id    = "bronze"
  friendly_name = "Bronze"
  description   = "Append-only raw history written by ingest jobs (all sources)"
  location      = var.location

  # Bronze is the only copy of data the sources don't keep themselves
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_bigquery_dataset" "silver" {
  dataset_id    = "silver"
  friendly_name = "Silver"
  description   = "Each source's cleaned copy, plus one-rule steps built on it (dbt)"
  location      = var.location
}

resource "google_bigquery_dataset" "gold" {
  dataset_id    = "gold"
  friendly_name = "Gold"
  description   = "Cross-source tables for the dashboard and models (dbt tables)"
  location      = var.location
}

# Sandboxes for local work (decision 0008), so test data never accumulates:
#   dev_bronze           local ingest runs: ingest/common/load.py writes here
#                        unless BQ_DATASET_ID says otherwise (the Cloud Run jobs
#                        set it to bronze). Its tables are defined below, so
#                        rows expire by partition instead of whole tables.
#   dev_silver, dev_gold local dbt builds (`--target local`, see
#                        transform/macros/generate_schema_name.sql); whole
#                        tables expire, and rebuilding recreates them.
resource "google_bigquery_dataset" "dev" {
  for_each = {
    dev_bronze = "Local ingest runs (ingest/common/load.py's default); rows expire after 7 days"
    dev_silver = "Local dbt builds (target local); tables expire after 7 days"
    dev_gold   = "Local dbt builds (target local); tables expire after 7 days"
  }

  dataset_id                  = each.key
  friendly_name               = "Dev ${title(trimprefix(each.key, "dev_"))}"
  description                 = each.value
  location                    = var.location
  default_table_expiration_ms = each.key == "dev_bronze" ? null : local.dev_retention_ms
}

# ── Bronze tables ─────────────────────────────────────────────────────────────

resource "google_bigquery_table" "bronze" {
  for_each = local.bronze_tables

  dataset_id          = google_bigquery_dataset.bronze.dataset_id
  table_id            = each.key
  description         = each.value.description
  deletion_protection = true

  # Partition by ingest day and cluster by grain key, so incremental silver
  # models read only new runs (decision 0003) and key lookups stay cheap
  clustering = each.value.clustering
  time_partitioning {
    type  = "DAY"
    field = "ingested_at"
  }

  schema = jsonencode(concat(each.value.columns, local.bronze_audit_columns))

  lifecycle {
    prevent_destroy = true
  }
}

# The same tables and schemas in dev_bronze, for local ingest runs. A run's
# rows expire with their ingest-day partition; the tables themselves stay.
resource "google_bigquery_table" "dev_bronze" {
  for_each = local.bronze_tables

  dataset_id          = google_bigquery_dataset.dev["dev_bronze"].dataset_id
  table_id            = each.key
  description         = "Dev copy of bronze.${each.key} for local ingest runs; rows expire after 7 days."
  deletion_protection = false

  clustering = each.value.clustering
  time_partitioning {
    type          = "DAY"
    field         = "ingested_at"
    expiration_ms = local.dev_retention_ms
  }

  schema = jsonencode(concat(each.value.columns, local.bronze_audit_columns))
}
