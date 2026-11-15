# 0018 — Power outages: DOE's EAGLE-I county history, a year's file at a time, mapped to load zones

**Status:** Accepted · **Date:** 2026-11-15

## Context
The storm outage model ([roadmap](../roadmap.md)) needs how many customers lost power, where, and when, to set against wind and snow. ISO-NE's outage feeds cover generators and transmission lines, not customers. EAGLE-I (Oak Ridge National Laboratory, for DOE) scrapes utilities' public outage maps every 15 minutes and totals them by county. Its live feed isn't public; its history is ([data-sources.md](../data-sources.md#doe-eagle-i)). Explored on 2026-11-15:

- **Published once a year** on figshare (article 24237376, no key): one CSV per year from 2014-11. Version 4 (2026-02-25) added 2025. Each file covers every US county: ~30 million rows and ~1.4 GB a year now. New England is 2.6% of that: 791,258 rows (~40 MB) in 2025, peaking at 47,121 customers out in Plymouth County on 2025-07-04.
- **Columns:** `fips_code`, `county`, `state`, `customers_out`, `run_start_time`, all in UTC per the dataset's paper (Brelsford et al., *Scientific Data*, 2024). They differ slightly by year: 2023's file calls `customers_out` `sum`, 2024's adds `total_customers`, and 2020's has some blank values.
- **Zeros are left out:** a county × interval with nobody out has no row, and neither does a gap in collection. The data can't tell the two apart.
- **Coverage is good in New England:** the dataset's own index puts it at 92–98% of the region's customers for 2018–2022. 2020 had weaker collection (69% of runs enabled), and New Hampshire's coverage in 2018 started at 17%.
- **Connecticut keeps its eight old counties** in every file through 2025, not the nine planning regions the Census switched to in 2022.
- **Downloads are slow and uneven:** 0.07–4.8 MB/s on the same day, and one connection dropped 84 MB into a file.

## Decision
- **One backfill-only job**, `eaglei-outages`, into `bronze.eaglei_outages`. For each year in the range, it finds that year's file by name through figshare's API, so a new version's file is found the same way. It reads the file as it downloads, a chunk at a time, and keeps the six New England states. One year is loaded at a time; memory holds one chunk plus that year's ~800,000 rows (1 GiB).
- **A broken download resumes** where it stopped, with a Range request for the rest (`download()` in `common/fetch.py`), rather than restarting a 1.4 GB file or failing a 12-file backfill.
- **The source's columns**, the same for every year: 2023's `sum` is read as `customers_out`, 2024's `total_customers` is left out, and blanks stay null. A missing column, or a year not yet published, fails the job.
- **Re-run once a year**, when the next file is posted (about February), for that year only ([runbook](../runbook.md#backfill-a-feed)). The [roadmap](../roadmap.md) dates it.
- **Counties map to load zones** through a seed, `eaglei_counties`: FIPS code, state, load zone, and EAGLE-I's modeled customer count per county (as of 2022). Each state is one zone except Massachusetts, whose 14 counties are each assigned whole:
  - SEMA: Barnstable, Bristol, Dukes, Nantucket, Plymouth
  - WCMA: Berkshire, Franklin, Hampden, Hampshire, Worcester
  - NEMA: Essex, Middlesex, Norfolk, Suffolk

  Middlesex and Norfolk cross zone lines; they go to NEMA, where their Boston-area towns are. Neither ISO-NE nor the utilities publish a county list.
- **Hourly by zone:** the mean of the hour's four 15-minute totals, so the zones add up to New England in every hour. Within an interval, a county without a row counts as zero, since that's what a missing row almost always means. There are two exceptions:
  - an interval with no row anywhere in New England is a gap in collection, and is left out of the mean;
  - a zone with no row all day wasn't covered that day, and stays null.

## Consequences
- **Size and cost:** ~800,000 rows (~40 MB) a year in bronze, ~7 million rows in all from 2014-11. The backfill downloads ~12 GB, roughly an hour on one vCPU at the speeds seen. Effectively $0.
- **Lags up to 14 months:** a year's outages arrive the next February. The storm model trains on history and can't be checked against last week's storm; EAGLE-I's live feed would need DOE access.
- **Massachusetts zone totals are approximate:** western Middlesex's outages count in NEMA rather than WCMA, and southern Norfolk's in NEMA rather than SEMA. State totals and New England's are exact.
- **Absence is ambiguous:** an hour of zero in a zone can be a calm hour, or a utility whose map wasn't scraped. The coverage notes here and in [data-quality.md](../data-quality.md) say how far to trust a year.

**2026-11-15 — figshare refuses Google Cloud.** The first backfill failed at its first request: figshare answered HTTP 403 from its AWS load balancer, on both attempts. A one-off execution that only made requests confirmed it: every figshare address (the API and the file downloads) refuses Cloud Run, whatever the client name; the same requests work from a workstation. Nothing was loaded. The planned way round: stage each year's file, gzipped, in a Cloud Storage landing bucket from a workstation (verified against figshare's MD5), and have the job read it from there. That needs the deployer to manage Cloud Storage, so it waits on that grant ([roadmap](../roadmap.md)). Until then the job, as built, can't run.
