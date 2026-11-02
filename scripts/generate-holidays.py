"""
Generate transform/seeds/us_holidays.csv: US holidays that move electricity
demand, by Eastern date, 2015–2035 (decision 0016).

Two lists, flagged per date:
  is_nerc_holiday     NERC's six off-peak holidays: New Year's Day, Memorial
                      Day, Independence Day, Labor Day, Thanksgiving,
                      Christmas. The grid runs them like Sundays. When one
                      falls on a Sunday, the Monday after is the holiday; on a
                      Saturday, it stays Saturday (NERC's rule).
  is_federal_holiday  The federal holidays as observed (pandas'
                      USFederalHolidayCalendar: Saturday → Friday, Sunday →
                      Monday), which shift demand less.

Rules, not a downloaded list, so it's reproducible and covers future years.
Run from the repo root with Python 3.13 and pandas, then commit the CSV:
  python scripts/generate-holidays.py
"""

# Import standard libraries
import csv
import datetime

# Import third party libraries
import pandas
from pandas.tseries.holiday import USFederalHolidayCalendar

FIRST_YEAR, LAST_YEAR = 2015, 2035
OUTPUT = 'transform/seeds/us_holidays.csv'


def nth_weekday(year, month, weekday, n):
    """The nth (1-based; -1 = last) given weekday (Monday = 0) of a month."""
    days = pandas.date_range(f"{year}-{month:02d}-01", periods=31, freq='D')
    matches = [day.date() for day in days if day.month == month and day.weekday() == weekday]
    return matches[n - 1] if n > 0 else matches[-1]


def sunday_to_monday(day):
    """NERC's rule: a holiday on Sunday moves to Monday; Saturday stays."""
    return day + datetime.timedelta(days=1) if day.weekday() == 6 else day


def nerc_holidays(year):
    """NERC's six holidays for a year, name → date."""
    return {
        "New Year's Day":   sunday_to_monday(datetime.date(year, 1, 1)),
        'Memorial Day':     nth_weekday(year, 5, 0, -1),
        'Independence Day': sunday_to_monday(datetime.date(year, 7, 4)),
        'Labor Day':        nth_weekday(year, 9, 0, 1),
        'Thanksgiving':     nth_weekday(year, 11, 3, 4),
        'Christmas':        sunday_to_monday(datetime.date(year, 12, 25)),
    }


# Federal holidays as observed, date → name
federal = USFederalHolidayCalendar().holidays(f"{FIRST_YEAR}-01-01", f"{LAST_YEAR}-12-31", return_name=True)
federal = {day.date(): name for day, name in federal.items()}

# NERC holidays, date → name
nerc = {day: name for year in range(FIRST_YEAR, LAST_YEAR + 1) for name, day in nerc_holidays(year).items()}

# One row per date on either list; a date on both takes the NERC name
with open(OUTPUT, 'w', newline='') as file:
    writer = csv.writer(file)
    writer.writerow(['holiday_date', 'holiday_name', 'is_nerc_holiday', 'is_federal_holiday'])
    for day in sorted(set(federal) | set(nerc)):
        writer.writerow([day.isoformat(), nerc.get(day) or federal[day], day in nerc, day in federal])
