"""
What every ingest job run shares: who it is, when it started, logging, and
failure reports.

Every ingest job follows the same three steps, each with its shared helper:
  1. Fetch from its source              → common/fetch.py (fetch())
  2. Shape the response into a DataFrame whose columns match its bronze table
  3. Load the DataFrame into bronze     → common/load.py (append_to_bronze())

Conventions:
  - A job lives in ingest/<job>/main.py and writes to bronze.<job> with "-"
    replaced by "_" (e.g. ingest/openmeteo-forecast → bronze.openmeteo_forecast).
  - A job that fails — through fail() or an uncaught exception — logs one
    structured failure report (report_failure()), which the job's alerting
    policy emails (infra/monitoring.tf). fetch.py and load.py import this
    module, so every job reports its failures without doing anything itself.
"""

# Import standard libraries
import datetime
import json
import logging
import os
import sys
import traceback

# Configure logging once for every job
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# One timestamp per run, stamped on every row the run writes. Silver relies on
# this: rows sharing the latest ingested_at are exactly the latest run's rows.
RUN_STARTED_AT = datetime.datetime.now(datetime.timezone.utc)

# Job name from the script's folder (e.g. "openmeteo-forecast"); drives the default
# bronze table name and the ingested_by audit value
JOB_NAME = os.path.basename(os.path.dirname(os.path.abspath(sys.argv[0])))


def report_failure(summary, details=''):
    """
    Log this run's failure as one structured entry (contract: infra/monitoring.tf).

    Cloud Run reads a JSON line on stdout as a structured log entry. Only the
    task's final attempt reports event "job_failed" at ERROR, which emails an
    alert; an attempt Cloud Run will retry logs "attempt_failed" at WARNING, so
    a transient error the retry absorbs sends nothing. CLOUD_RUN_TASK_ATTEMPT
    (0-based) is set by Cloud Run; MAX_RETRIES by Terraform.
    """
    is_final_attempt = int(os.getenv('CLOUD_RUN_TASK_ATTEMPT', '0')) >= int(os.getenv('MAX_RETRIES', '0'))
    print(json.dumps({
        'severity': 'ERROR' if is_final_attempt else 'WARNING',
        'event':    'job_failed' if is_final_attempt else 'attempt_failed',
        'job':      f"ingest-{JOB_NAME}",
        'message':  f"{summary}\n\n{details}".strip(),
    }), flush=True)


def fail(message):
    """Report a failure and exit non-zero so Cloud Run marks the execution failed."""
    report_failure(message)
    sys.exit(1)


def _report_uncaught_exception(exc_type, exc_value, exc_traceback):
    """Report any exception a job didn't handle, with its traceback, then exit as usual."""
    details = ''.join(traceback.format_exception(exc_type, exc_value, exc_traceback))
    report_failure(f"{exc_type.__name__}: {exc_value}", details)
    sys.__excepthook__(exc_type, exc_value, exc_traceback)


# Every job imports this module (through fetch.py and load.py), so this covers
# unexpected errors in any job (a changed API response, a shaping bug) as well
# as the fail() paths
sys.excepthook = _report_uncaught_exception
