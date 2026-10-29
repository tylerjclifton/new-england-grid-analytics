"""
Step 1 of every ingest job: fetch from the source.

fetch() is a plain HTTP GET that turns a network error or a non-200 response
into a failed job (with a failure report, see common/run.py) instead of an
exception the job has to handle.
"""

# Import third party libraries
import requests

# Import shared ingest helpers
from common.run import fail


def fetch(url, params=None, headers=None, timeout=60):
    """GET a URL, exiting the job on a network error or non-200 response."""
    try:
        response = requests.get(url, params=params, headers=headers, timeout=timeout)
    except requests.exceptions.RequestException as error:
        fail(f"Request to {url} failed: {error}")

    if response.status_code != 200:
        fail(f"Request to {url} returned HTTP {response.status_code}")

    return response
