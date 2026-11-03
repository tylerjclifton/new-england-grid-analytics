{% macro new_ingest_runs(relation) -%}
  {#-
    The rows of `relation` (a __base view over bronze) from ingest runs an
    incremental model hasn't processed yet: every row on a first build or
    --full-refresh, otherwise only those ingested after the newest run already
    in the table being built (MAX(ingested_at) in `this`).

    That newest run is compiled into the query as a literal timestamp, so
    BigQuery prunes bronze's ingested_at partitions through the view; a
    subquery in the WHERE clause wouldn't. The pruning is what keeps scheduled
    runs cheap as bronze grows (decision 0003).

    Usage — the first CTE of an incremental model:
      new_runs AS (
          {{ new_ingest_runs(ref('isone_da_lmp__base')) }}
      )
  -#}
  {%- set processed_through = none -%}
  {%- if is_incremental() and execute -%}
    {%- set result = run_query("SELECT FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%E6S', MAX(ingested_at)) FROM " ~ this) -%}
    {%- set processed_through = result.columns[0].values()[0] -%}
  {%- endif -%}
        SELECT *
        FROM {{ relation }}
        {%- if processed_through %}
        WHERE ingested_at > TIMESTAMP '{{ processed_through }}'
        {%- endif %}
{%- endmacro %}
