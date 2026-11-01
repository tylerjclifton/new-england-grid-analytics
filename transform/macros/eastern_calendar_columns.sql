{% macro eastern_calendar_columns(column) -%}
  {#-
    Calendar columns for a UTC hour, in New England's local time (decision
    0002: stored in UTC, local time derived): the Eastern date and hour, the
    weekday (1 = Sunday … 7 = Saturday), and whether it's a weekend. On the
    night clocks fall back, hour 1 appears twice; on the night they spring
    forward, hour 2 doesn't appear.

    Usage — in a select with a UTC hour column:
      SELECT hour_start_at, {{ eastern_calendar_columns('hour_start_at') }}, …
  -#}
    DATE({{ column }}, 'America/New_York')                                        AS date_local,
    EXTRACT(HOUR FROM DATETIME({{ column }}, 'America/New_York'))                 AS hour_local,
    EXTRACT(DAYOFWEEK FROM DATETIME({{ column }}, 'America/New_York'))            AS day_of_week,
    EXTRACT(DAYOFWEEK FROM DATETIME({{ column }}, 'America/New_York')) IN (1, 7)  AS is_weekend
{%- endmacro %}
