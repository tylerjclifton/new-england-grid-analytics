"""
Ingest job tests: each script's shaping logic against canned API responses.

What each test pins down is the contract with bronze — one row per expected
grain, correct types, and the source's quirks handled.
"""

import pandas as pd
import pytest

# ── openmeteo-forecast ────────────────────────────────────────────────────────

ZONES = ['ME', 'NH', 'VT', 'CT', 'RI', 'SEMA', 'WCMA', 'NEMA']
VARIABLES = ['temperature_2m', 'dew_point_2m', 'cloud_cover', 'shortwave_radiation',
             'wind_speed_10m', 'wind_speed_100m', 'precipitation', 'snowfall']


def openmeteo_point(index, times=('2026-10-28T00:00', '2026-10-28T01:00'), missing=None):
    """One point of an Open-Meteo multi-location response; values encode the point's index."""
    hourly = {'time': list(times)}
    for variable in VARIABLES:
        hourly[variable] = [None if variable == missing else float(index) for _ in times]
    return {
        'latitude': 40.0 + index, 'longitude': -70.0 - index, 'elevation': 10.0 * index,
        'utc_offset_seconds': 0, 'timezone': 'GMT', 'hourly': hourly,
    }


def openmeteo_response(**kwargs):
    """A response covering every load zone, in request order."""
    return [openmeteo_point(i, **kwargs) for i in range(len(ZONES))]


def test_forecast_one_row_per_zone_per_hour(run_job):
    df = run_job('openmeteo-forecast', [openmeteo_response()])

    assert len(df) == len(ZONES) * 2
    assert not df.duplicated(['load_zone', 'time']).any()
    assert sorted(df['load_zone'].unique()) == sorted(ZONES)


def test_forecast_points_matched_to_zones_in_request_order(run_job):
    """Open-Meteo answers in request order; each zone gets its own point's values."""
    df = run_job('openmeteo-forecast', [openmeteo_response()])

    by_zone = df.groupby('load_zone').first()
    for index, zone in enumerate(ZONES):
        assert by_zone.loc[zone, 'temperature_2m'] == float(index)
        assert by_zone.loc[zone, 'latitude'] == 40.0 + index


def test_forecast_times_are_utc(run_job):
    df = run_job('openmeteo-forecast', [openmeteo_response()])

    assert str(df['time'].dt.tz) == 'UTC'
    assert df['time'].min() == pd.Timestamp('2026-10-28T00:00', tz='UTC')


def test_forecast_requests_utc_and_every_zone(run_job):
    run_job('openmeteo-forecast', [openmeteo_response()])

    params = run_job.requests[0]['params']
    assert params['timezone'] == 'GMT'
    assert len(params['latitude'].split(',')) == len(ZONES)
    assert params['hourly'].split(',') == VARIABLES


def test_forecast_missing_value_is_null(run_job):
    df = run_job('openmeteo-forecast', [openmeteo_response(missing='snowfall')])

    assert df['snowfall'].isna().all()
    assert df['snowfall'].dtype == 'float64'


def test_forecast_fails_if_a_point_is_missing(run_job):
    """Fewer points than requested means zones can't be matched safely: fail, don't guess."""
    with pytest.raises(ValueError):
        run_job('openmeteo-forecast', [openmeteo_response()[:-1]])
