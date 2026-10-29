{% macro keep_latest_version(key_columns) -%}
  {#-
    Keep only the most recently ingested row for each key.

    Bronze tables are append-only, so the same record (a weather hour, a price
    interval) appears once per ingest run that saw it. Silver models use this
    to collapse those versions down to the latest one.

    Usage — placed after FROM/WHERE in a query over a bronze table:
      SELECT * FROM {{ ref('openmeteo_forecast__base') }}
      {{ keep_latest_version(['load_zone', 'hour_at']) }}

    Compiles to:
      QUALIFY ROW_NUMBER() OVER (
          PARTITION BY load_zone, hour_at ORDER BY ingested_at DESC
      ) = 1
  -#}
  QUALIFY ROW_NUMBER() OVER (
      PARTITION BY {{ key_columns | join(', ') }} ORDER BY ingested_at DESC
  ) = 1
{%- endmacro %}
