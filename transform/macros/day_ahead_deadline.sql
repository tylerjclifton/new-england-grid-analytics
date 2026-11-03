{% macro day_ahead_deadline(hour_column) -%}
  {#-
    The moment a day-ahead forecast for an hour has to be in: 10:00 Eastern on
    the day before the hour's Eastern date, the day-ahead market's bid deadline
    (decision 0017). A forecast issued after it couldn't have been used to bid.

    Usage — the last version issued by the deadline, per hour:
      WHERE issued_at <= {{ day_ahead_deadline('hour_start_at') }}
      QUALIFY ROW_NUMBER() OVER (PARTITION BY hour_start_at ORDER BY issued_at DESC) = 1
  -#}
    TIMESTAMP(
        DATETIME(DATE_SUB(DATE({{ hour_column }}, 'America/New_York'), INTERVAL 1 DAY), TIME '10:00:00'),
        'America/New_York'
    )
{%- endmacro %}
