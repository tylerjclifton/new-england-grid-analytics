"""
Step 1 of every ingest job: fetch from the source.

fetch() is an HTTP GET that turns a network error or a non-200 response into a
failed job (with a failure report, see common/run.py) instead of an exception
the job has to handle. Sources that need a login pass `auth` (HTTP basic auth,
e.g. ISO-NE through common/isone.py).

download() is for a file too large to hold in memory (eaglei-outages): a
file-like object over the response that reads as the file arrives. A
connection that breaks mid-file is picked up where it stopped, with a Range
request for the rest, up to MAX_ATTEMPTS times; a long download over a slow
link would otherwise have to start over.

Transient failures are retried first: a dropped connection, a rate limit (HTTP
429; ISO-NE sends them under a sustained backfill), or a server error (5xx),
up to MAX_ATTEMPTS with doubling waits, or the source's Retry-After if it gives
one. Anything else (401, 404, …) fails at once: retrying won't change it.

A key sent as a query parameter (EIA's api_key) would appear in the URL of a
network error's message, and so in the logs and the alert email: fetch()
replaces the value of any parameter in SECRET_PARAMS with *** before reporting.
"""

# Import standard libraries
import io
import logging
import time

# Import third party libraries
import requests
import urllib3

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


def fetch(url, params=None, headers=None, auth=None, timeout=60, stream=False):
    """
    GET a URL, retrying transient failures; exits the job if it can't get a
    200 (or the 206 a Range request gets, download()).
    """
    secrets = [str(value) for key, value in (params or {}).items() if key in SECRET_PARAMS and value]

    for attempt in range(1, MAX_ATTEMPTS + 1):
        retry_after = None
        try:
            response = requests.get(url, params=params, headers=headers, auth=auth, timeout=timeout, stream=stream)
        except requests.exceptions.RequestException as error:
            problem = redact(f"Request to {url} failed: {error}", secrets)
        else:
            if response.status_code in (200, 206):
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


def download(url, timeout=60):
    """
    The file at `url` as a binary file-like object, read as it downloads, that
    resumes after a broken connection (see the module docstring). Use it in a
    `with` block, so the connection closes when reading is done.
    """
    return io.BufferedReader(_ResumingDownload(url, timeout), buffer_size=1 << 20)


class _ResumingDownload(io.RawIOBase):
    """download()'s raw stream: the response's bytes, reopened from `position` after each break."""

    def __init__(self, url, timeout):
        self.url      = url
        self.timeout  = timeout
        self.position = 0  # bytes read so far
        self.breaks   = 0
        self.response = None
        self.response = self._request()

    def readable(self):
        return True

    def readinto(self, buffer):
        while True:
            try:
                data = self.response.raw.read(len(buffer))
            except urllib3.exceptions.HTTPError as error:  # a dropped connection or a stalled read
                self.breaks += 1
                if self.breaks >= MAX_ATTEMPTS:
                    fail(f"Download of {self.url} broke {self.breaks} times, the last at byte {self.position}: {error}")
                logging.warning(f"Download of {self.url} broke at byte {self.position} ({error}); resuming")
                self.response.close()
                self.response = self._request()
                continue
            buffer[:len(data)] = data
            self.position += len(data)
            return len(data)

    def close(self):
        if not self.closed and self.response is not None:
            self.response.close()
        super().close()

    def _request(self):
        """The file from `position` on: all of it at first, the rest after a break."""
        if not self.position:
            return fetch(self.url, timeout=self.timeout, stream=True)
        response = fetch(self.url, headers={'Range': f"bytes={self.position}-"}, timeout=self.timeout, stream=True)
        if response.status_code != 206:
            fail(f"{self.url} ignored a request to resume at byte {self.position} (HTTP {response.status_code})")
        return response


def redact(message, secrets):
    """`message` with every secret value replaced by ***."""
    for secret in secrets:
        message = message.replace(secret, '***')
    return message
