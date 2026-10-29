"""
Tests for the shared ingest helpers in ingest/common/: run.py (failure
reports), fetch.py, and load.py (append to bronze).
"""

import json
import sys
from types import SimpleNamespace

import pandas as pd
import pytest

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


def test_fetch_exits_on_http_error(monkeypatch):
    monkeypatch.setattr(fetch.requests, "get", lambda *a, **k: SimpleNamespace(status_code=503))

    with pytest.raises(SystemExit) as exit_info:
        fetch.fetch("https://example.test")

    assert exit_info.value.code == 1


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
