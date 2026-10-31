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


# ── ISO-NE (common/isone.py, isone-fuel-mix, isone-system-load) ───────────────

@pytest.fixture
def isone_login(monkeypatch):
    """The ISO Express login, as Secret Manager provides it to the jobs."""
    monkeypatch.setenv('ISONE_WS_USERNAME', 'user')
    monkeypatch.setenv('ISONE_WS_PASSWORD', 'pass')


def fuel_mix_day(*snapshots):
    """A /genfuelmix/day response: each snapshot is (BeginDate, {fuel: MW})."""
    return {'GenFuelMixes': {'GenFuelMix': [
        {'BeginDate': begin, 'GenMw': mw, 'FuelCategoryRollup': fuel, 'FuelCategory': fuel,
         'MarginalFlag': 'Y' if fuel == 'Natural Gas' else 'N'}
        for begin, fuels in snapshots for fuel, mw in fuels.items()
    ]}}


def system_load_day(*begins):
    """A /fiveminutesystemload/day response with one interval per BeginDate."""
    return {'FiveMinSystemLoads': {'FiveMinSystemLoad': [
        {'BeginDate': begin, 'LoadMw': 9482.781, 'NativeLoad': 8978.581, 'ArdDemand': 504.2,
         'SystemLoadBtmPv': 14050.781, 'NativeLoadBtmPv': 13546.581}
        for begin in begins
    ]}}


def test_isone_days_are_yesterday_then_today_in_eastern_time():
    from common.isone import days_to_fetch

    assert days_to_fetch(today=pd.Timestamp('2026-11-01').date()) == ['20261031', '20261101']


def test_isone_requests_each_day_with_the_login(run_job, isone_login):
    run_job('isone-fuel-mix', [fuel_mix_day(), fuel_mix_day()])

    urls = [request['url'] for request in run_job.requests]
    assert len(urls) == 2
    assert all(url.startswith('https://webservices.iso-ne.com/api/v1.1/genfuelmix/day/') for url in urls)
    assert all(url.endswith('.json') for url in urls)
    assert urls == sorted(urls)  # oldest day first


def test_isone_empty_day_shapes_give_no_rows(run_job, isone_login):
    """A day with no data comes back as an empty object or an empty list."""
    df = run_job('isone-fuel-mix', [{'GenFuelMixes': {}}, {'GenFuelMixes': {'GenFuelMix': []}}])

    assert df.empty
    assert list(df.columns) == ['BeginDate', 'FuelCategory', 'FuelCategoryRollup', 'GenMw', 'MarginalFlag']


def test_isone_lone_record_as_object_is_one_row(run_job, isone_login):
    lone = {'GenFuelMixes': {'GenFuelMix': fuel_mix_day(('2026-10-30T12:00:00.000-04:00', {'Nuclear': 2110}))
                                                ['GenFuelMixes']['GenFuelMix'][0]}}
    df = run_job('isone-fuel-mix', [lone, fuel_mix_day()])

    assert len(df) == 1


def test_isone_times_convert_to_utc_through_the_fall_back_hour(run_job, isone_login):
    """1:30 AM happens twice when clocks fall back; the offsets keep them apart."""
    df = run_job('isone-system-load', [
        system_load_day('2026-10-31T23:55:00.000-04:00'),
        system_load_day('2026-11-01T01:30:00.000-04:00', '2026-11-01T01:30:00.000-05:00'),
    ])

    assert str(df['BeginDate'].dt.tz) == 'UTC'
    assert list(df['BeginDate']) == [pd.Timestamp('2026-11-01T03:55', tz='UTC'),
                                     pd.Timestamp('2026-11-01T05:30', tz='UTC'),
                                     pd.Timestamp('2026-11-01T06:30', tz='UTC')]


def test_isone_missing_field_fails_the_job(run_job, isone_login):
    """A changed API should stop the load, not write nulls into bronze."""
    day = system_load_day('2026-10-30T12:00:00.000-04:00')
    del day['FiveMinSystemLoads']['FiveMinSystemLoad'][0]['SystemLoadBtmPv']

    with pytest.raises(SystemExit):
        run_job('isone-system-load', [day, system_load_day()])


def test_isone_without_login_fails_before_fetching(run_job, monkeypatch):
    monkeypatch.delenv('ISONE_WS_USERNAME', raising=False)
    monkeypatch.delenv('ISONE_WS_PASSWORD', raising=False)

    with pytest.raises(SystemExit):
        run_job('isone-fuel-mix', [])
    assert run_job.requests == []


def test_fuel_mix_one_row_per_snapshot_per_fuel(run_job, isone_login):
    df = run_job('isone-fuel-mix', [
        fuel_mix_day(('2026-10-30T12:00:00.000-04:00', {'Natural Gas': 6646, 'Nuclear': 2110, 'Solar': 900})),
        # Solar has stopped by evening, so it's absent, not 0
        fuel_mix_day(('2026-10-31T18:29:55.000-04:00', {'Natural Gas': 7000, 'Nuclear': 2110})),
    ])

    assert len(df) == 5
    assert not df.duplicated(['BeginDate', 'FuelCategory']).any()
    assert df['GenMw'].dtype == 'float64'
    assert set(df.loc[df['MarginalFlag'] == 'Y', 'FuelCategory']) == {'Natural Gas'}


def test_system_load_keeps_every_measure_as_float(run_job, isone_login):
    df = run_job('isone-system-load', [system_load_day('2026-10-30T12:00:00.000-04:00'), system_load_day()])

    assert list(df.columns) == ['BeginDate', 'LoadMw', 'NativeLoad', 'ArdDemand', 'SystemLoadBtmPv', 'NativeLoadBtmPv']
    assert (df.drop(columns='BeginDate').dtypes == 'float64').all()
    # Rooftop solar is the gap between the two loads
    assert df['SystemLoadBtmPv'].iloc[0] - df['LoadMw'].iloc[0] == pytest.approx(4568, abs=1)
