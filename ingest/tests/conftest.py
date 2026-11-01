"""
Shared fixtures for ingest job tests.

Each job is a script (ingest/<job>/main.py) that runs top to bottom: fetch →
shape → append_to_bronze(). `run_job` executes a script for real with the two
edges replaced — HTTP responses are canned, and the DataFrame handed to
append_to_bronze is captured instead of loaded into BigQuery.
"""

import json
import runpy
import sys
from pathlib import Path
from unittest import mock

import pytest

INGEST_DIR = Path(__file__).resolve().parents[1]


class FakeResponse:
    """Minimal stand-in for requests.Response."""

    def __init__(self, body, status_code=200):
        self.status_code = status_code
        self._body = body

    def json(self):
        return self._body if isinstance(self._body, (dict, list)) else json.loads(self._body)

    @property
    def text(self):
        return self._body if isinstance(self._body, str) else json.dumps(self._body)


@pytest.fixture
def run_job(monkeypatch):
    """
    run_job(job, responses) → the first DataFrame passed to append_to_bronze
    (or None).

    `responses` is a list of bodies returned by successive HTTP GETs. Each GET's
    URL and params are recorded in run_job.requests, and every DataFrame loaded
    (one per batch, for jobs that load in batches) in run_job.loads.
    """

    def _run(job, responses):
        import common.fetch as fetch
        import common.load as load

        bodies = iter(responses)
        _run.requests.clear()
        _run.loads.clear()

        def fake_get(url, params=None, **kwargs):
            _run.requests.append({"url": url, "params": params or {}})
            return FakeResponse(next(bodies))

        monkeypatch.setattr(fetch.requests, "get", fake_get)
        monkeypatch.setattr(load, "append_to_bronze", _run.loads.append)

        script = INGEST_DIR / job / "main.py"
        with mock.patch.object(sys, "argv", [str(script)]):
            runpy.run_path(str(script), run_name="__main__")
        return _run.loads[0] if _run.loads else None

    _run.requests = []
    _run.loads = []
    return _run
