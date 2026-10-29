{% test unique_combination(model, columns) %}
  {#-
    Grain test: no two rows share the same values across `columns`.
    Fails with one row per duplicated key combination.

    Usage (model-level, in a properties yml):
      data_tests:
        - unique_combination:
            arguments:
              columns: [service_date, line_name]
  -#}
SELECT
    {{ columns | join(', ') }},
    COUNT(*) AS row_count
FROM {{ model }}
GROUP BY {{ columns | join(', ') }}
HAVING COUNT(*) > 1
{% endtest %}
