"""
Ingest: customers without power in each New England county, every 15
minutes, from DOE's EAGLE-I — backfill only

Source:     EAGLE-I's recorded outages (Oak Ridge National Laboratory, for
            DOE), published once a year on figshare (article 24237376, no key;
            decision 0018): one CSV per year for every US county, ~1.4 GB,
            fips_code, county, state, customers_out, run_start_time (UTC, the
            interval's start). A county × interval with nobody out has no row,
            and neither does a gap in collection.
Cadence:    None. Run as a one-off backfill (BACKFILL_START / BACKFILL_END,
            common/backfill.py), and again for each new year once it's posted
            (about February; docs/runbook.md).
Each run:   Each year's file overlapping the range, read as it downloads, a
            chunk at a time (common/fetch.py, download(): a broken connection
            resumes where it stopped), keeping New England's rows in the range;
            loaded a year at a time.
Writes to:  bronze.eaglei_outages (append) — one row per county × interval × run
"""

# Import standard libraries
import logging

# Import third party libraries
import pandas

# Import shared ingest helpers
from common.backfill import backfill_days, is_backfill
from common.fetch import download, fetch
from common.load import append_to_bronze
from common.run import fail

# The dataset's latest version, listing its files (a new year adds one)
ARTICLE_URL = 'https://api.figshare.com/v2/articles/24237376'
FILE_NAME   = 'eaglei_outages_{year}.csv'

# The columns kept: every year has these. 2023's file calls customers_out
# "sum"; 2024's adds total_customers, left behind since no other year has it.
COLUMNS        = ['fips_code', 'county', 'state', 'customers_out', 'run_start_time']
COLUMN_ALIASES = {'sum': 'customers_out'}

STATES     = {'Connecticut', 'Maine', 'Massachusetts', 'New Hampshire', 'Rhode Island', 'Vermont'}
CHUNK_ROWS = 500_000  # rows parsed at a time, of ~30 million a year nationwide


# Backfill only: the files are yearly, so there's nothing to schedule
if not is_backfill():
    fail("eaglei-outages runs only as a backfill: set BACKFILL_START and BACKFILL_END (docs/runbook.md)")

days = backfill_days()
first_interval = pandas.Timestamp(days[0], tz='UTC')
after_last     = pandas.Timestamp(days[-1], tz='UTC') + pandas.Timedelta(days=1)

# Each year's file name → download URL
files = {file['name']: file['download_url'] for file in fetch(ARTICLE_URL).json()['files']}

for year in range(days[0].year, days[-1].year + 1):

    # ── Fetch and shape ───────────────────────────────────────────────────────

    name = FILE_NAME.format(year=year)
    if name not in files:
        fail(f"EAGLE-I has no {name} (yet?); its files: {', '.join(sorted(files))}")

    # Parse as it downloads (resuming if the connection breaks), keeping New
    # England: memory holds one chunk and the year's kept rows (~800,000),
    # never the national file. A renamed or missing column fails here, loudly.
    kept = []
    with download(files[name], timeout=300) as csv_file:
        chunks = pandas.read_csv(csv_file, dtype=str, chunksize=CHUNK_ROWS,
                                 usecols=lambda column: column in COLUMNS or column in COLUMN_ALIASES)
        for chunk in chunks:
            chunk = chunk.rename(columns=COLUMN_ALIASES)
            missing = sorted(set(COLUMNS) - set(chunk.columns))
            if missing:
                fail(f"{name} is missing expected columns: {', '.join(missing)}")
            kept.append(chunk[chunk['state'].isin(STATES)])
    df = pandas.concat(kept, ignore_index=True) if kept else pandas.DataFrame(columns=COLUMNS)

    # UTC timestamps; customers out as a whole number (a few are blank: null)
    df['run_start_time'] = pandas.to_datetime(df['run_start_time'], format='%Y-%m-%d %H:%M:%S', utc=True)
    df['customers_out']  = pandas.to_numeric(df['customers_out']).astype('Int64')
    df = df[(df['run_start_time'] >= first_interval) & (df['run_start_time'] < after_last)][COLUMNS]
    logging.info(f"{name}: kept {len(df)} New England rows")

    # ── Write ─────────────────────────────────────────────────────────────────

    append_to_bronze(df, time_column='run_start_time')
