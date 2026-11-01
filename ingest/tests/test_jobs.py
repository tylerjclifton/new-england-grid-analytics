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


def lmp_day(*begins, location_id=4000, location_type='HUB', location_name='.H.INTERNAL_HUB', wrapper='FiveMinLmps'):
    """A price response (/fiveminutelmp or /hourlylmp) for one location, one record per BeginDate."""
    record_key = {'FiveMinLmps': 'FiveMinLmp', 'HourlyLmps': 'HourlyLmp'}[wrapper]
    return {wrapper: {record_key: [
        {'BeginDate': begin,
         'Location': {'@LocId': str(location_id), '@LocType': location_type, '$': location_name},
         'LmpTotal': 31.75, 'EnergyComponent': 31.33, 'CongestionComponent': 0.05, 'LossComponent': 0.37}
        for begin in begins
    ]}}


def test_isone_records_unwrap_three_levels_and_empty_days():
    """The zonal load feed nests one level deeper than the others, and is empty as {"isone_web_services": {}}."""
    from common.isone import records

    assert records({'a': {'b': {'c': [{'x': 1}, {'x': 2}]}}}) == [{'x': 1}, {'x': 2}]
    assert records({'isone_web_services': {}}) == []
    assert records({'a': {'b': {'x': 1, 'y': 2}}}) == [{'x': 1, 'y': 2}]


def test_isone_flatten_location():
    from common.isone import flatten_location

    record = lmp_day('2026-10-30T00:00:00.000-04:00')['FiveMinLmps']['FiveMinLmp'][0]
    flat = flatten_location(record)

    assert 'Location' not in flat
    assert (flat['LocId'], flat['LocType'], flat['LocName']) == (4000, 'HUB', '.H.INTERNAL_HUB')


def test_rt_lmp_pulls_prelim_recent_days_and_final_older_days(run_job, isone_login):
    from common.isone import PRICING_LOCATIONS

    calls = 2 * 2 * len(PRICING_LOCATIONS)  # 2 versions × 2 days × locations
    run_job('isone-rt-lmp', [lmp_day('2026-10-30T12:00:00.000-04:00')] * calls)
    df = pd.concat(run_job.loads)  # one load per version

    urls = [request['url'] for request in run_job.requests]
    assert len(urls) == calls
    assert sum('/fiveminutelmp/prelim/day/' in url for url in urls) == calls // 2
    assert sum('/fiveminutelmp/final/day/' in url for url in urls) == calls // 2
    assert {url.split('/location/')[1].removesuffix('.json') for url in urls} == {str(id) for id in PRICING_LOCATIONS}

    # The prelim and final windows never share a day
    prelim_days = {url.split('/day/')[1].split('/')[0] for url in urls if '/prelim/' in url}
    final_days  = {url.split('/day/')[1].split('/')[0] for url in urls if '/final/' in url}
    assert prelim_days.isdisjoint(final_days) and max(final_days) < min(prelim_days)

    assert sorted(df['LmpType'].unique()) == ['final', 'prelim']
    assert list(df.columns[:4]) == ['BeginDate', 'LocId', 'LocType', 'LocName']
    assert df['LmpTotal'].dtype == 'float64'
    assert str(df['BeginDate'].dt.tz) == 'UTC'


def test_rt_lmp_empty_final_days_still_load_prelim(run_job, isone_login):
    """Finals not published yet: prelim rows still load."""
    from common.isone import PRICING_LOCATIONS

    per_type = 2 * len(PRICING_LOCATIONS)
    df = run_job('isone-rt-lmp', [lmp_day('2026-10-30T12:00:00.000-04:00')] * per_type
                                 + [{'FiveMinLmps': {}}] * per_type)

    assert set(df['LmpType']) == {'prelim'}
    assert len(df) == per_type


def test_da_lmp_pulls_today_and_tomorrow(run_job, isone_login):
    from common.isone import PRICING_LOCATIONS

    calls = 2 * len(PRICING_LOCATIONS)
    df = run_job('isone-da-lmp', [lmp_day('2026-11-01T00:00:00.000-04:00', wrapper='HourlyLmps')] * calls)

    urls = [request['url'] for request in run_job.requests]
    assert len(urls) == calls
    assert all('/hourlylmp/da/final/day/' in url for url in urls)
    days = sorted({url.split('/day/')[1].split('/')[0] for url in urls})
    assert len(days) == 2 and pd.Timestamp(days[1]) - pd.Timestamp(days[0]) == pd.Timedelta(days=1)
    assert len(df) == calls


def zonal_load_day(*begins):
    """A /fiveminuteestimatedzonalload/day response: every zone at each interval."""
    return {'isone_web_services': {'five_min_estimated_zonal_loads': {'five_min_estimated_zonal_load': [
        {'interval_begin_date': begin, 'load_zone_id': 4000 + index, 'load_zone_name': f'.Z.ZONE{index}',
         'estimated_load_mw': 1000.5, 'estimated_btm_pv_mw': 250}
        for begin in begins for index in range(1, 9)
    ]}}}


def test_zonal_load_one_row_per_interval_per_zone(run_job, isone_login):
    df = run_job('isone-zonal-load', [zonal_load_day('2026-10-30T12:00:00.000-04:00'), {'isone_web_services': {}}])

    assert len(df) == 8
    assert not df.duplicated(['interval_begin_date', 'load_zone_id']).any()
    assert df['load_zone_id'].dtype == 'int64'
    assert df['estimated_btm_pv_mw'].dtype == 'float64'
    assert df['interval_begin_date'].iloc[0] == pd.Timestamp('2026-10-30T16:00', tz='UTC')


# ── ISO-NE backfill mode (decision 0013) ──────────────────────────────────────

@pytest.fixture
def backfill(monkeypatch):
    """backfill(start, end): put common.backfill in backfill mode, as the env vars would."""
    import common.backfill as backfill_mode

    def _set(start, end):
        monkeypatch.setattr(backfill_mode, 'BACKFILL_START', start)
        monkeypatch.setattr(backfill_mode, 'BACKFILL_END', end)
        monkeypatch.setattr(backfill_mode, 'PAUSE_SECONDS', 0)
    return _set


def test_isone_normal_run_is_one_batch():
    from common.isone import day_batches, days_to_fetch

    assert day_batches() == [days_to_fetch()]
    assert day_batches(['20261101']) == [['20261101']]


def test_isone_backfill_batches_the_range_by_month(backfill):
    from common.backfill import BATCH_DAYS as BACKFILL_BATCH_DAYS
    from common.isone import day_batches

    backfill('20260101', '20260305')
    batches = day_batches(['ignored'])

    # 64 days: Jan 1–31, Feb 1–Mar 3, Mar 4–5
    assert [len(batch) for batch in batches] == [BACKFILL_BATCH_DAYS, BACKFILL_BATCH_DAYS, 2]
    assert batches[0][0] == '20260101' and batches[-1][-1] == '20260305'


@pytest.mark.parametrize('start, end', [('20260305', '20260101'), ('20260101', None), ('not-a-day', '20260101')])
def test_isone_backfill_bad_range_fails(backfill, start, end):
    from common.isone import day_batches

    backfill(start, end)
    with pytest.raises(SystemExit):
        day_batches()


def test_rt_lmp_backfill_pulls_final_prices_only(run_job, isone_login, backfill):
    from common.isone import PRICING_LOCATIONS

    backfill('20250101', '20250102')
    calls = 2 * len(PRICING_LOCATIONS)
    df = run_job('isone-rt-lmp', [lmp_day('2025-01-01T12:00:00.000-05:00')] * calls)

    urls = [request['url'] for request in run_job.requests]
    assert len(urls) == calls
    assert all('/fiveminutelmp/final/day/2025010' in url for url in urls)
    assert set(df['LmpType']) == {'final'}


def test_fuel_mix_backfill_loads_each_batch(run_job, isone_login, backfill):
    """A long range loads month by month, not all at once."""
    backfill('20260101', '20260210')
    run_job('isone-fuel-mix', [fuel_mix_day(('2026-01-01T12:00:00.000-05:00', {'Nuclear': 3300}))] * 41)

    assert [len(df) for df in run_job.loads] == [31, 10]


def test_rt_lmp_hourly_refuses_to_run_on_a_schedule(run_job, isone_login):
    with pytest.raises(SystemExit):
        run_job('isone-rt-lmp-hourly', [])
    assert run_job.requests == []


def test_rt_lmp_hourly_backfill(run_job, isone_login, backfill):
    from common.isone import PRICING_LOCATIONS

    backfill('20200101', '20200101')
    hour = lmp_day('2020-01-01T00:00:00.000-05:00', wrapper='HourlyLmps')
    df = run_job('isone-rt-lmp-hourly', [hour] * len(PRICING_LOCATIONS))

    assert all('/hourlylmp/rt/final/day/20200101/location/' in request['url'] for request in run_job.requests)
    assert len(df) == len(PRICING_LOCATIONS)
    assert df['BeginDate'].iloc[0] == pd.Timestamp('2020-01-01T05:00', tz='UTC')


# ── EIA (common/eia.py, eia-region-data, eia-fuel-type-data, eia-region-data-bulk) ──

@pytest.fixture
def eia_key(monkeypatch):
    """The EIA key, as Secret Manager provides it to the jobs."""
    monkeypatch.setenv('EIA_API_KEY', 'test-key')


def eia_page(records, total=None):
    """One page of an EIA API response."""
    return {'response': {'total': str(total if total is not None else len(records)), 'data': records}}


def eia_region_record(period, type_code='D', value='11614'):
    return {'period': period, 'respondent': 'ISNE', 'respondent-name': 'ISO New England', 'type': type_code,
            'type-name': 'Demand', 'value': value, 'value-units': 'megawatthours'}


def test_eia_normal_run_is_the_last_two_weeks():
    import datetime

    from common.eia import hour_ranges

    assert hour_ranges(now=datetime.datetime(2026, 11, 1, 5, tzinfo=datetime.timezone.utc)) == [('2026-10-18T00', None)]


def test_eia_backfill_ranges_are_months_of_whole_utc_days(backfill):
    from common.eia import hour_ranges

    backfill('20190101', '20190215')
    assert hour_ranges() == [('2019-01-01T00', '2019-01-31T23'), ('2019-02-01T00', '2019-02-15T23')]


def test_eia_region_data_shapes_and_requests(run_job, eia_key):
    df = run_job('eia-region-data', [eia_page([eia_region_record('2019-01-01T06'),
                                               eia_region_record('2019-01-01T06', 'DF', '11500')])])

    params = run_job.requests[0]['params']
    assert run_job.requests[0]['url'].endswith('/electricity/rto/region-data/data/')
    assert params['facets[respondent][]'] == 'ISNE' and params['frequency'] == 'hourly'
    assert list(df.columns) == ['period', 'respondent', 'respondent_name', 'type', 'type_name', 'value', 'value_units']
    assert df['period'].iloc[0] == pd.Timestamp('2019-01-01T06', tz='UTC')
    assert df['value'].dtype == 'float64' and df['value'].tolist() == [11614.0, 11500.0]


def test_eia_pages_until_the_total(run_job, eia_key, monkeypatch):
    import common.eia as eia

    monkeypatch.setattr(eia, 'PAGE_SIZE', 2)
    pages = [eia_page([eia_region_record('2019-01-01T00'), eia_region_record('2019-01-01T01')], total=3),
             eia_page([eia_region_record('2019-01-01T02')], total=3)]
    df = run_job('eia-region-data', pages)

    assert [request['params']['offset'] for request in run_job.requests] == [0, 2]
    assert len(df) == 3


def test_eia_null_value_is_null(run_job, eia_key):
    df = run_job('eia-region-data', [eia_page([eia_region_record('2019-01-01T06', value=None)])])

    assert df['value'].isna().all()


def test_eia_error_body_fails_without_the_key(run_job, eia_key, capsys):
    with pytest.raises(SystemExit):
        run_job('eia-region-data', [{'error': 'Invalid key test-key'}])

    output = capsys.readouterr().out
    assert 'test-key' not in output and 'returned no data' in output


def test_eia_without_key_fails_before_fetching(run_job, monkeypatch):
    monkeypatch.delenv('EIA_API_KEY', raising=False)

    with pytest.raises(SystemExit):
        run_job('eia-region-data', [])
    assert run_job.requests == []


def test_eia_fuel_type_data(run_job, eia_key):
    record = {'period': '2019-01-01T06', 'respondent': 'ISNE', 'respondent-name': 'ISO New England',
              'fueltype': 'NUC', 'type-name': 'Nuclear', 'value': '4013', 'value-units': 'megawatthours'}
    df = run_job('eia-fuel-type-data', [eia_page([record])])

    assert run_job.requests[0]['url'].endswith('/electricity/rto/fuel-type-data/data/')
    assert df.loc[0, 'fueltype'] == 'NUC' and df.loc[0, 'value'] == 4013.0


BULK_HEADER = ('"Balancing Authority","Data Date","Hour Number","Local Time at End of Hour",'
               '"UTC Time at End of Hour","Demand Forecast (MW)","Demand (MW)","Net Generation (MW)",'
               '"Total Interchange (MW)"\n')


def test_eia_bulk_keeps_isne_in_range_as_long_rows(run_job, backfill):
    backfill('20150701', '20150701')
    csv = BULK_HEADER + (
        'ISNE,07/01/2015,1,07/01/2015 1:00:00 AM,07/01/2015 5:00:00 AM,11810,12583,11322,-1261\n'
        'ISNE,07/01/2015,20,07/01/2015 8:00:00 PM,07/02/2015 12:00:00 AM,15000,"15,100",13000,-2100\n'  # next UTC day
        'CISO,07/01/2015,1,07/01/2015 1:00:00 AM,07/01/2015 8:00:00 AM,1,2,3,4\n'
    )
    df = run_job('eia-region-data-bulk', [csv])

    assert run_job.requests[0]['url'].endswith('EIA930_BALANCE_2015_Jul_Dec.csv')
    assert len(df) == 4  # one ISNE hour in range × 4 measures
    assert set(df['type']) == {'D', 'DF', 'NG', 'TI'}
    assert df.set_index('type').loc['D', 'value'] == 12583.0
    assert df['period'].unique().tolist() == [pd.Timestamp('2015-07-01T05', tz='UTC')]
    assert list(df.columns) == ['period', 'respondent', 'respondent_name', 'type', 'type_name', 'value', 'value_units']


def test_eia_bulk_fetches_each_half_year_once(run_job, backfill):
    backfill('20150601', '20160105')
    run_job('eia-region-data-bulk', [BULK_HEADER] * 3)

    assert [request['url'].rsplit('/', 1)[-1] for request in run_job.requests] == [
        'EIA930_BALANCE_2015_Jan_Jun.csv', 'EIA930_BALANCE_2015_Jul_Dec.csv', 'EIA930_BALANCE_2016_Jan_Jun.csv']


def test_eia_bulk_refuses_to_run_on_a_schedule(run_job):
    with pytest.raises(SystemExit):
        run_job('eia-region-data-bulk', [])
