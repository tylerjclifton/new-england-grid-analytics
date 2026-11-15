# Data quality

What the data covers, where it has gaps, and how well the sources agree with each other. Checked 2026-11-02 against production silver and gold, after every backfill ([0013](decisions/0013-isone-backfill.md), [0014](decisions/0014-eia-930.md), [0015](decisions/0015-weather-history.md)); ISO-NE's forecasts ([0017](decisions/0017-isone-forecasts.md)), past weather forecasts and gas prices on 2026-11-15. Re-run the queries below to refresh the numbers; the checks that should keep holding are permanent tests (last section).

## Coverage and gaps

Hours a source should have, from where its history starts to three days ago (when revisions and final prices are in), and how many it's missing:

| Source | Covered from | Hours | Missing | Notes |
|---|---|---|---|---|
| EIA demand and ISO-NE's day-ahead forecast | 2015-07-01 | 99,332 | 8 (0.008%) | |
| Fuel mix | 2019-06-01 | 64,989 | 96 (0.15%) | Scattered days, at most 7 hours on one (2020-12-06): ISO-NE publishing gaps. Another 39 hours have a single snapshot |
| Hub real-time and day-ahead prices | 2019-06-01 | 64,989 | 0 | No real-time price older than 4 days is still preliminary |
| Five-minute real-time prices | 2024-06-01 | | 0 partial hours | Every hour has all 12 intervals |
| System load (with rooftop solar) | 2024-06-01 | 21,145 | 0 | Every hour has all 12 intervals |
| Zonal load | 2025-02-01 | 15,386 hours × 8 zones | 31 partial hours | Fewer than 12 intervals in a zone-hour |
| Weather (reanalysis) | 2015-07-01 | 794,864 zone-hours | 0 | |
| ISO-NE's day-ahead load forecast, system and zones | 2019-06-01 | 65,305 (× 8 zones) | 0 | Every hour has a version issued by the day-ahead deadline ([0017](decisions/0017-isone-forecasts.md)) |
| ISO-NE's day-ahead wind forecast | 2019-06-02 | 65,277 | 0 | The first publication in the history (2019-06-01) covers only that day's later hours |
| Weather forecast as issued, 1 and 2 days ahead | 2021-01-01 | 51,048 per lead (× 8 zones) | 0 | Through 2026-10-28; temperature throughout, other variables from 2024 |
| Henry Hub gas price ([0019](decisions/0019-natural-gas-prices.md)) | 2015-01-02 | 2,998 trading days | 1 (2018-01-05, null in EIA's data) | Every hour in gold has a price: weekends and holidays take the last trade |
| Power plants' gas price by state | 2015-01 | 140 months | MA 0, CT 1, RI 39, ME 94, NH 105, VT all 140 | Withheld by EIA where a state has few plants; latest is about two months back |

Gold keeps every hour regardless ([0016](decisions/0016-first-gold-tables.md)): a missing hour shows as nulls, never as a dropped row, so a model or chart sees the gap.

## Cross-checks between sources

| Check | Hours | Result | What it shows |
|---|---|---|---|
| ISO-NE system load vs. EIA-930 demand | 21,143 (2024-06 on) | **Identical on average** (mean difference 0 MW, correlation 1.0000); 4 hours more than 1% apart (below) | EIA's demand for ISO New England is ISO-NE's system load, and the hour-end → hour-start shift applied to EIA ([0014](decisions/0014-eia-930.md)) is right; an hour off would show at once |
| ISO-NE fuel mix total vs. EIA-930 net generation | 64,895 (2019-06 on) | Mean absolute difference 0.77%, correlation 0.991; ISO-NE 85 MW lower on average | The snapshot mean ([0016](decisions/0016-first-gold-tables.md)) is close to the hour's energy, not exact |
| Hourly real-time price: mean of five-minute vs. ISO-NE's hourly feed | 46,233 (2024-06 to 2024-12, Hub and zones) | Mean absolute difference 0.35¢, at most 2¢; none over 5¢ | The two real-time histories join without a seam ([0013](decisions/0013-isone-backfill.md)) |
| Eight zonal loads vs. system native load | 15,386 (2025-02 on) | Mean absolute difference 0.06%; 13 hours more than 1% apart (below); zones' rooftop solar sums to the system's within 0.1 MW | The zonal feed is a split of the system, not a separate estimate |
| ISO-NE's day-ahead demand forecast (EIA's copy) vs. EIA demand | 99,326 (2015-07 on) | Mean absolute error 2.62%; 194 MW low on average | The benchmark a load model has to beat ([0017](decisions/0017-isone-forecasts.md) adds every version, per zone) |

## Known oddities

- **EIA interchange glitches:** two single-hour spikes (−12,307 MWh at 2021-03-01 04:00 UTC and −10,411 at 2021-03-02 04:00, between hours near −2,400). Kept as reported; `eia_region_data__latest`'s range test warns on them every run.
- **System load disagrees with EIA in 4 hours**, by 3–9%: 2025-02-28 13:00, 2026-09-11 17:00, and 2026-10-14 19:00–20:00 UTC. On 2026-10-14 the zones disagree with the system too (below), so ISO-NE's five-minute system load looks wrong in those hours.
- **Zones disagree with the system in 13 hours**, by 1–7%, all with every interval present: 2025-02-27 21:00, 2025-04-02 20:00–21:00, 2025-04-23 14:00, 2025-05-20 18:00, 2025-09-16 18:00, 2025-11-02 06:00, 2025-11-19 21:00, 2026-09-15 18:00, 2026-09-25 17:00, 2026-10-14 20:00–21:00, 2026-10-20 20:00 UTC.
- **ISO-NE's zonal forecast has an impossible version:** Connecticut at −2,358 MW, issued 2021-08-20 for 2021-08-23 02:00 UTC. Kept as issued; `isone_zonal_load_forecast__issued`'s range test warns on it.
- **Henry Hub spikes in cold snaps:** $23.86 on 2021-02-17 (Winter Storm Uri), $13.20 on 2024-01-12, and $30.72 on 2026-01-23, two days before oil passed gas in New England's fuel mix. New England's own winter premium shows monthly: Massachusetts power plants paid $25.08/MCF in January 2023 and $19.72 in January 2026, against about $3.50 in summer.
- **Fuel mix is a snapshot mean**, so generation by fuel and total generation are close to the hour's energy, not exact (see the cross-check above).
- **History starts differ by source**, so a model's training window depends on the columns it uses; each gold table's description lists where each column starts.

## Permanent checks

The checks that should keep holding run in every transform (`dbt build`), as warnings: a source drifting shows in the run's output and logs without blocking the build. The cross-checks look at the last 10 days, so they warn about new data; the historical exceptions above stay listed here instead of warning every run.

| Test | Warns when |
|---|---|
| `tests/assert_system_load_matches_eia.sql` | ISO-NE's system load and EIA's demand differ by more than 1% in an hour of the last 10 days |
| `tests/assert_zones_sum_to_native_load.sql` | The eight zones' load is more than 1% off system native load in an hour of the last 10 days |
| `tests/assert_no_recent_gaps.sql` | A core source (EIA demand, system load, fuel mix, Hub prices, ISO-NE's load forecast) is missing an hour between 10 and 3 days ago: a feed that keeps running but loses hours, which the freshness check can't see |
