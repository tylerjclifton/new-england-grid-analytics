"""
Transform job entrypoint (Dockerfile CMD)

Runs, in order, stopping at the first failure:
  1. `dbt build` — models + tests in DAG order; a failing test skips everything
     downstream of it, so bad data never reaches gold
  2. `dbt source freshness` — fails the run if an ingest job has stopped
     writing to bronze (thresholds in models/bronze/_bronze__sources.yml)
Both use the gcp target (attached service account, no keyfile) unless
DBT_TARGET says otherwise — e.g. DBT_TARGET=local to try it against the dev
datasets.

dbt's output streams to the job's logs unchanged. On failure, the job also logs
one structured failure report holding dbt's failure summary — which models,
tests, or sources failed and why — which the transform's alerting policy emails
(contract: infra/monitoring.tf).
"""

# Import standard libraries
import json
import os
import re
import subprocess
import sys

TARGET = os.getenv('DBT_TARGET', 'gcp')

# Step name → command
STEPS = {
    'dbt build':            ['dbt', 'build', '--profiles-dir', '.', '--target', TARGET],
    'dbt source freshness': ['dbt', 'source', 'freshness', '--profiles-dir', '.', '--target', TARGET],
}

# Lines of dbt output kept in a failure report (the email shows them verbatim)
MAX_DETAIL_LINES = 40

# dbt prefixes most lines with a timestamp, e.g. "01:36:39  " (some lines are
# only a timestamp)
TIMESTAMP = re.compile(r'^\d{2}:\d{2}:\d{2}\s*')


def run(command):
    """Run a dbt command, streaming its output; return (exit code, output lines)."""
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env={**os.environ, 'DBT_USE_COLORS': 'false'},  # plain text for logs and email
    )
    lines = []
    for line in process.stdout:
        print(line, end='', flush=True)
        lines.append(TIMESTAMP.sub('', line.rstrip()))
    return process.wait(), lines


def failure_details(lines):
    """
    The part of dbt's output that says what failed:
      - `dbt build` with failing nodes: its closing summary ("Completed with
        N errors…" followed by each failure and its compiled SQL path)
      - a dbt crash (auth, compilation): everything from "Encountered an error"
      - `dbt source freshness`: each source that is stale or errored
    Falls back to the last lines of output.
    """
    for marker in ('Completed with', 'Encountered an error'):
        starts = [i for i, line in enumerate(lines) if marker in line]
        if starts:
            details = lines[starts[-1]:]
            break
    else:
        details = [line for line in lines if 'ERROR' in line] or lines

    details = [line for line in details if line.strip()]
    return '\n'.join(details[-MAX_DETAIL_LINES:])


def report_failure(summary, details):
    """
    Log the failure as one structured entry: event "job_failed" emails an alert.
    Same contract as ingest/common/run.py; the transform never retries
    (MAX_RETRIES = 0), so every failure is final.
    """
    is_final_attempt = int(os.getenv('CLOUD_RUN_TASK_ATTEMPT', '0')) >= int(os.getenv('MAX_RETRIES', '0'))
    print(json.dumps({
        'severity': 'ERROR' if is_final_attempt else 'WARNING',
        'event':    'job_failed' if is_final_attempt else 'attempt_failed',
        'job':      'transform',
        'message':  f"{summary}\n\n{details}".strip(),
    }), flush=True)


if __name__ == '__main__':
    for step, command in STEPS.items():
        exit_code, output = run(command)
        if exit_code != 0:
            report_failure(f"`{step}` failed (exit code {exit_code})", failure_details(output))
            sys.exit(exit_code)
