"""
Tests for the shared ingest helpers in ingest/common/: run.py (failure
reports), fetch.py, and load.py (append to bronze).
"""

import io
import json
import sys
from types import SimpleNamespace

import pandas as pd
import pytest
import urllib3

from common import fetch, load, run


class FakeClient:
    """Records the BigQuery load instead of running it."""

    loads = []

    def __init__(self, project=None):
        pass

    def get_table(self, table_ref):
        return SimpleNamespace(schema=[load.bigquery.SchemaField("load_zone", "STRING")])

    def load_table_from_dataframe(self, df, table_ref, job_config):
        FakeClient.loads.append(SimpleNamespace(df=df, table_ref=table_ref, job_config=job_config))
        return SimpleNamespace(result=lambda: None)


@pytest.fixture
def fake_bigquery(monkeypatch):
    FakeClient.loads = []
    monkeypatch.setattr(load.bigquery, "Client", FakeClient)
    monkeypatch.setenv("BQ_PROJECT_ID", "proj")
    monkeypatch.setenv("BQ_DATASET_ID", "bronze")
    monkeypatch.setenv("BQ_TABLE_ID", "openmeteo_forecast")
    return FakeClient.loads


def test_append_adds_audit_columns_and_appends(fake_bigquery):
    load.append_to_bronze(pd.DataFrame({"load_zone": ["ME", "NH"]}))

    load_job = fake_bigquery[0]
    assert load_job.table_ref == "proj.bronze.openmeteo_forecast"
    assert load_job.job_config.write_disposition == "WRITE_APPEND"
    # Every row in a run shares one timestamp — silver depends on it
    assert load_job.df["ingested_at"].nunique() == 1
    assert load_job.df["ingested_at"].iloc[0] == run.RUN_STARTED_AT
    assert load_job.df["ingested_by"].str.startswith("ingest-").all()


def test_append_loads_against_the_live_table_schema(fake_bigquery):
    load.append_to_bronze(pd.DataFrame({"load_zone": ["ME"]}))

    assert [field.name for field in fake_bigquery[0].job_config.schema] == ["load_zone"]


def test_append_defaults_to_dev_bronze(fake_bigquery, monkeypatch):
    """Without BQ_DATASET_ID (a local run), rows go to dev_bronze, never production (decision 0008)."""
    monkeypatch.delenv("BQ_DATASET_ID")

    load.append_to_bronze(pd.DataFrame({"load_zone": ["ME"]}))

    assert fake_bigquery[0].table_ref == "proj.dev_bronze.openmeteo_forecast"


def test_append_skips_empty_frames(fake_bigquery):
    load.append_to_bronze(pd.DataFrame())

    assert fake_bigquery == []


@pytest.fixture
def no_sleep(monkeypatch):
    """Record fetch()'s retry waits instead of sleeping through them."""
    waits = []
    monkeypatch.setattr(fetch.time, "sleep", waits.append)
    return waits


def responses(*statuses, retry_after=None):
    """A requests.get stand-in answering with each status in turn."""
    answers = iter(statuses)
    headers = {"Retry-After": retry_after} if retry_after else {}
    return lambda *a, **k: SimpleNamespace(status_code=next(answers), headers=headers)


def test_fetch_exits_after_retrying_a_server_error(monkeypatch, no_sleep):
    monkeypatch.setattr(fetch.requests, "get", responses(*[503] * fetch.MAX_ATTEMPTS))

    with pytest.raises(SystemExit) as exit_info:
        fetch.fetch("https://example.test")

    assert exit_info.value.code == 1
    assert no_sleep == [15, 30, 60, 120, 240]  # a wait before each retry, doubling


def test_fetch_retries_a_rate_limit_then_succeeds(monkeypatch, no_sleep):
    monkeypatch.setattr(fetch.requests, "get", responses(429, 429, 200))

    assert fetch.fetch("https://example.test").status_code == 200
    assert len(no_sleep) == 2


def test_fetch_honors_retry_after(monkeypatch, no_sleep):
    monkeypatch.setattr(fetch.requests, "get", responses(429, 200, retry_after="30"))

    fetch.fetch("https://example.test")
    assert no_sleep == [30]


def test_fetch_does_not_retry_a_client_error(monkeypatch, no_sleep):
    """A 401 or 404 won't change on retry: fail at once."""
    monkeypatch.setattr(fetch.requests, "get", responses(404))

    with pytest.raises(SystemExit):
        fetch.fetch("https://example.test")
    assert no_sleep == []


def test_fetch_redacts_the_api_key_from_network_errors(monkeypatch, no_sleep, capsys):
    """The key travels in the URL; a connection error's message would otherwise carry it to the alert email."""
    def refuse(url, params=None, **kwargs):
        message = f"Max retries exceeded with url: /data?api_key={params['api_key']}"
        raise fetch.requests.exceptions.ConnectionError(message)
    monkeypatch.setattr(fetch.requests, "get", refuse)

    with pytest.raises(SystemExit):
        fetch.fetch("https://api.example.test/data", params={"api_key": "SECRET123"})

    output = capsys.readouterr()
    assert "SECRET123" not in output.out + output.err
    assert "api_key=***" in output.out


class BreakingStream(io.BytesIO):
    """A response body whose connection drops after `limit` bytes (None: never)."""

    def __init__(self, data, limit=None):
        super().__init__(data)
        self.limit = limit

    def read(self, size=-1):
        if self.limit is not None:
            if self.tell() >= self.limit:
                raise urllib3.exceptions.ProtocolError("Connection broken: IncompleteRead")
            size = self.limit - self.tell() if size < 0 else min(size, self.limit - self.tell())
        return super().read(size)


def file_server(body, break_at=None, resume_status=206):
    """A requests.get stand-in serving `body`, breaking the first connection at byte `break_at`."""
    def get(url, headers=None, **kwargs):
        get.ranges.append((headers or {}).get("Range"))
        if not headers:
            return SimpleNamespace(status_code=200, raw=BreakingStream(body, break_at), close=lambda: None)
        start = int(headers["Range"].removeprefix("bytes=").removesuffix("-"))
        return SimpleNamespace(status_code=resume_status, raw=BreakingStream(body[start:]), close=lambda: None)
    get.ranges = []
    return get


def test_download_resumes_where_the_connection_broke(monkeypatch, no_sleep):
    body = b"fips_code,county\n" + b"09001,Fairfield\n" * 1000
    server = file_server(body, break_at=5000)
    monkeypatch.setattr(fetch.requests, "get", server)

    with fetch.download("https://files.test/big.csv") as file:
        assert file.read() == body
    assert server.ranges == [None, "bytes=5000-"]


def test_download_fails_if_the_server_ignores_the_range(monkeypatch, no_sleep):
    """A 200 to a resume would be the whole file again: rows read twice."""
    monkeypatch.setattr(fetch.requests, "get", file_server(b"x" * 100, break_at=50, resume_status=200))

    with pytest.raises(SystemExit), fetch.download("https://files.test/big.csv") as file:
        file.read()


# ── Failure reports (the alerting contract in infra/monitoring.tf) ────────────

def last_report(capsys):
    """The structured failure report a job printed to stdout."""
    return json.loads(capsys.readouterr().out.strip().splitlines()[-1])


def test_fail_on_final_attempt_reports_job_failed(monkeypatch, capsys):
    monkeypatch.setenv("CLOUD_RUN_TASK_ATTEMPT", "1")
    monkeypatch.setenv("MAX_RETRIES", "1")

    with pytest.raises(SystemExit):
        run.fail("Request to https://example.test returned HTTP 503")

    report = last_report(capsys)
    assert report["severity"] == "ERROR"
    assert report["event"] == "job_failed"
    assert report["job"].startswith("ingest-")
    assert report["message"] == "Request to https://example.test returned HTTP 503"


def test_fail_before_a_retry_only_warns(monkeypatch, capsys):
    # Cloud Run will retry, so this attempt must not trigger an alert email
    monkeypatch.setenv("CLOUD_RUN_TASK_ATTEMPT", "0")
    monkeypatch.setenv("MAX_RETRIES", "1")

    with pytest.raises(SystemExit):
        run.fail("Request to https://example.test returned HTTP 503")

    report = last_report(capsys)
    assert report["severity"] == "WARNING"
    assert report["event"] == "attempt_failed"


def test_uncaught_exception_reports_traceback(monkeypatch, capsys):
    monkeypatch.setattr(run.sys, "__excepthook__", lambda *args: None)
    try:
        {}["data"]
    except KeyError as error:
        sys.excepthook(type(error), error, error.__traceback__)

    report = last_report(capsys)
    assert report["event"] == "job_failed"
    assert report["message"].startswith("KeyError: 'data'")
    assert "Traceback (most recent call last)" in report["message"]
