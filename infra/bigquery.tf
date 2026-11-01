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

  # The fields every ISO-NE price record has (both price tables); the nested
  # Location is flattened into LocId / LocType / LocName by the ingest
  isone_lmp_columns = [
    { name = "BeginDate", type = "TIMESTAMP", description = "Start of the interval the price is for (UTC; ISO-NE sends Eastern time with its offset)" },
    { name = "LocId", type = "INTEGER", description = "Pricing location ID: 4000 the Hub, 4001–4008 the load zones" },
    { name = "LocType", type = "STRING", description = "Location type: HUB or LOAD ZONE" },
    { name = "LocName", type = "STRING", description = "Location name, e.g. .H.INTERNAL_HUB, .Z.MAINE" },
    { name = "LmpTotal", type = "FLOAT", description = "Locational marginal price, $/MWh: EnergyComponent + CongestionComponent + LossComponent" },
    { name = "EnergyComponent", type = "FLOAT", description = "Energy component, $/MWh (the same everywhere in New England)" },
    { name = "CongestionComponent", type = "FLOAT", description = "Congestion component, $/MWh (nonzero when transmission limits bind)" },
    { name = "LossComponent", type = "FLOAT", description = "Marginal loss component, $/MWh" },
  ]

  # The fields every EIA-930 region-data record has (the API's names, "-" as
  # "_"); shared by the API table and the 2015–2018 bulk backfill table
  eia_region_columns = [
    { name = "period", type = "TIMESTAMP", description = "End of the hour the value is for (UTC; EIA labels hours by their end)" },
    { name = "respondent", type = "STRING", description = "Balancing authority, ISNE (ISO New England)" },
    { name = "respondent_name", type = "STRING", description = "Balancing authority name" },
    { name = "type", type = "STRING", description = "Measure: D demand, DF day-ahead demand forecast, NG net generation, TI total interchange" },
    { name = "type_name", type = "STRING", description = "Measure name, e.g. Demand" },
    { name = "value", type = "FLOAT", description = "Value for the hour, MWh (MW averaged over the hour); null when EIA has none" },
    { name = "value_units", type = "STRING", description = "Units, megawatthours" },
  ]

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

    isone_zonal_load = {
      description = "ISO-NE five-minute estimated load per load zone (decision 0010), with each zone's behind-the-meter (rooftop) solar estimate. The zones add up to system native load, and their solar to the system estimate. Each run re-pulls yesterday and today. Grain: five-minute interval × load zone × ingest run."
      clustering  = ["load_zone_id", "interval_begin_date"]
      columns = [
        { name = "interval_begin_date", type = "TIMESTAMP", description = "Start of the five-minute interval (UTC; ISO-NE sends Eastern time with its offset)" },
        { name = "load_zone_id", type = "INTEGER", description = "ISO-NE load zone location ID, 4001–4008 (same IDs as the price feeds' LocId)" },
        { name = "load_zone_name", type = "STRING", description = "ISO-NE load zone name, e.g. .Z.NEMASSBOST" },
        { name = "estimated_load_mw", type = "FLOAT", description = "Estimated load in the zone, MW (the zones add up to system native load)" },
        { name = "estimated_btm_pv_mw", type = "FLOAT", description = "Estimated behind-the-meter (rooftop) solar in the zone, MW" },
      ]
    }

    isone_rt_lmp = {
      description = "ISO-NE five-minute real-time prices (LMPs) at the Hub and the eight load zones (decision 0012). Preliminary prices for yesterday and today, final prices for 2 and 3 days ago; LmpType says which. Grain: five-minute interval × location × version × ingest run."
      clustering  = ["LocId", "BeginDate"]
      columns = concat(local.isone_lmp_columns, [
        { name = "LmpType", type = "STRING", description = "Which version of the price: prelim (published within minutes) or final (about a day later); set by the ingest from the feed it called" },
      ])
    }

    isone_rt_lmp_hourly = {
      description = "ISO-NE hourly real-time prices (LMPs), final, at the Hub and the eight load zones: a backfill of the years before ISO-NE's five-minute history begins (decision 0013). Each hourly price is the mean of that hour's five-minute prices. Grain: hour × location × ingest run."
      clustering  = ["LocId", "BeginDate"]
      columns     = local.isone_lmp_columns
    }

    eia_region_data = {
      description = "EIA-930 hourly demand, day-ahead demand forecast, net generation and interchange for ISO New England, from the API (decision 0014). Each daily run re-pulls two weeks, since EIA revises recent hours. History from 2019-01-01. Grain: hour × measure × ingest run."
      clustering  = ["type", "period"]
      columns     = local.eia_region_columns
    }

    eia_region_data_bulk = {
      description = "EIA-930 hourly demand, day-ahead demand forecast, net generation and interchange for ISO New England, 2015-07 to 2018-12, from EIA's six-month bulk files, reshaped into the API's long form (decision 0014). Backfill only. Grain: hour × measure × ingest run."
      clustering  = ["type", "period"]
      columns     = local.eia_region_columns
    }

    eia_fuel_type_data = {
      description = "EIA-930 hourly net generation by fuel for ISO New England, from the API (decision 0014). Each daily run re-pulls two weeks. History from 2019-01-01. A fuel not reported for an hour is null or absent. Grain: hour × fuel × ingest run."
      clustering  = ["fueltype", "period"]
      columns = [
        { name = "period", type = "TIMESTAMP", description = "End of the hour the value is for (UTC; EIA labels hours by their end)" },
        { name = "respondent", type = "STRING", description = "Balancing authority, ISNE (ISO New England)" },
        { name = "respondent_name", type = "STRING", description = "Balancing authority name" },
        { name = "fueltype", type = "STRING", description = "Fuel code: COL, NG, NUC, OIL, WAT, PS, SUN, SNB, WND, BAT, OTH" },
        { name = "type_name", type = "STRING", description = "Fuel name, e.g. Natural Gas" },
        { name = "value", type = "FLOAT", description = "Net generation for the hour, MWh; null when EIA has none" },
        { name = "value_units", type = "STRING", description = "Units, megawatthours" },
      ]
    }

    isone_da_lmp = {
      description = "ISO-NE hourly day-ahead prices (LMPs) at the Hub and the eight load zones (decision 0012): the market's forecast of real-time prices, final when published (around midday the day before). Each run pulls today and tomorrow. Grain: hour × location × ingest run."
      clustering  = ["LocId", "BeginDate"]
      columns     = local.isone_lmp_columns
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
