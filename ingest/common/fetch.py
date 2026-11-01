"""
Step 1 of every ingest job: fetch from the source.

fetch() is an HTTP GET that turns a network error or a non-200 response into a
failed job (with a failure report, see common/run.py) instead of an exception
the job has to handle. Sources that need a login pass `auth` (HTTP basic auth,
e.g. ISO-NE through common/isone.py).

Transient failures are retried first: a dropped connection, a rate limit (HTTP
429; ISO-NE sends them under a sustained backfill), or a server error (5xx),
up to MAX_ATTEMPTS with doubling waits, or the source's Retry-After if it gives
one. Anything else (401, 404, …) fails at once: retrying won't change it.

A key sent as a query parameter (EIA's api_key) would appear in the URL of a
network error's message, and so in the logs and the alert email: fetch()
replaces the value of any parameter in SECRET_PARAMS with *** before reporting.
"""

# Import standard libraries
import logging
import time

# Import third party libraries
import requests

# Import shared ingest helpers
from common.run import fail

# Query parameters whose values never appear in a failure report
SECRET_PARAMS = {'api_key'}

# Retries for transient failures: statuses worth retrying, attempts in all, and
# the first wait, doubling after each attempt (15, 30, 60, 120, 240 s: ~8
# minutes in all, enough to outlast ISO-NE's rate-limit block; decision 0013)
RETRY_STATUSES  = {429, 500, 502, 503, 504}
MAX_ATTEMPTS    = 6
BACKOFF_SECONDS = 15


def fetch(url, params=None, headers=None, auth=None, timeout=60):
    """GET a URL, retrying transient failures; exits the job if it can't get a 200."""
    secrets = [str(value) for key, value in (params or {}).items() if key in SECRET_PARAMS and value]

    for attempt in range(1, MAX_ATTEMPTS + 1):
        retry_after = None
        try:
            response = requests.get(url, params=params, headers=headers, auth=auth, timeout=timeout)
        except requests.exceptions.RequestException as error:
            problem = redact(f"Request to {url} failed: {error}", secrets)
        else:
            if response.status_code == 200:
                return response
            problem = f"Request to {url} returned HTTP {response.status_code}"
            if response.status_code not in RETRY_STATUSES:
                break
            retry_after = response.headers.get('Retry-After')

        if attempt < MAX_ATTEMPTS:
            wait = int(retry_after) if retry_after and retry_after.isdigit() else BACKOFF_SECONDS * 2 ** (attempt - 1)
            logging.warning(f"{problem}; retrying in {wait} s (attempt {attempt} of {MAX_ATTEMPTS})")
            time.sleep(wait)

    fail(problem)


def redact(message, secrets):
    """`message` with every secret value replaced by ***."""
    for secret in secrets:
        message = message.replace(secret, '***')
    return message
