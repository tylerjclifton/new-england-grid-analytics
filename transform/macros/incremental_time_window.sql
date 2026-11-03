{#
  Partitioning and merge window for incremental silver models (decision 0003).

  A merge has to find each new row's match in the table being built. Without
  a window it scans the whole table, so every run costs more as history grows.
  Partitioned by month on the model's time column, with incremental_predicates
  limiting the merge to recent partitions, a run reads only the last month or
  two, however long the history is.

  The window is 35 days back from now, which covers every key a scheduled run
  can bring: ISO-NE re-pulls yesterday and today (prices 3 days back), EIA and
  the reanalysis two weeks, and forecasts reach ahead into the future (always
  inside the window). A backfill brings older keys: rebuild with
  --full-refresh after one (docs/runbook.md, "Backfill a feed"), or rows it
  re-delivers would be added again rather than merged; the unique tests would
  catch that.

  Usage — in an incremental model's config:
    partition_by=monthly_partitions('hour_start_at'),
    incremental_predicates=recent_merge_window('hour_start_at'),
#}

{% macro monthly_partitions(column) -%}
  {{- return({'field': column, 'data_type': 'timestamp', 'granularity': 'month'}) -}}
{%- endmacro %}

{% macro recent_merge_window(column) -%}
  {{- return(['DBT_INTERNAL_DEST.' ~ column ~ ' >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 35 DAY)']) -}}
{%- endmacro %}
