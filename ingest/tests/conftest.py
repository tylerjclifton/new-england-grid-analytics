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
    run_job(job, responses) → DataFrame passed to append_to_bronze (or None).

    `responses` is a list of bodies returned by successive HTTP GETs. Each GET's
    URL and params are recorded in run_job.requests.
    """

    def _run(job, responses):
        import common.fetch as fetch
        import common.load as load

        bodies = iter(responses)
        captured = {}
        _run.requests.clear()

        def fake_get(url, params=None, **kwargs):
            _run.requests.append({"url": url, "params": params or {}})
            return FakeResponse(next(bodies))

        monkeypatch.setattr(fetch.requests, "get", fake_get)
        monkeypatch.setattr(load, "append_to_bronze", lambda df: captured.setdefault("df", df))

        script = INGEST_DIR / job / "main.py"
        with mock.patch.object(sys, "argv", [str(script)]):
            runpy.run_path(str(script), run_name="__main__")
        return captured.get("df")

    _run.requests = []
    return _run
