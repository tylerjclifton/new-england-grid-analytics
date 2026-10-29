{% macro last_processed_run() -%}
  {#-
    The newest bronze ingest run an incremental model has already processed
    (MAX(ingested_at) in the table being built), as a timestamp string
    ('YYYY-MM-DD HH:MM:SS.ffffff'), or none on a first build or --full-refresh.

    The model compiles it into its query as a literal, so BigQuery prunes
    bronze's ingested_at partitions; a subquery in the WHERE clause wouldn't.
    That pruning is what keeps scheduled runs cheap as bronze grows (decision 0003).

    Usage:
      {%- set processed_through = last_processed_run() -%}
      ...
      {%- if processed_through %}
      WHERE ingested_at > TIMESTAMP '{{ processed_through }}'
      {%- endif %}
  -#}
  {%- if is_incremental() and execute -%}
    {%- set result = run_query("SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%E6S', MAX(ingested_at)) FROM " ~ this) -%}
    {{- return(result.columns[0].values()[0]) -}}
  {%- endif -%}
  {{- return(none) -}}
{%- endmacro %}
