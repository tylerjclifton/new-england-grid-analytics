{% test accepted_range(model, column_name, min_value=none, max_value=none) %}
  {#-
    Plausibility test: every non-null value lies within [min_value, max_value].
    Either bound may be omitted. Fails with each out-of-range row.

    Usage (column-level, in a properties yml):
      - name: gated_entries
        data_tests:
          - accepted_range:
              arguments:
                min_value: 0
  -#}
SELECT *
FROM {{ model }}
WHERE {{ column_name }} IS NOT NULL
  AND (
    FALSE
    {%- if min_value is not none %} OR {{ column_name }} < {{ min_value }}{% endif %}
    {%- if max_value is not none %} OR {{ column_name }} > {{ max_value }}{% endif %}
  )
{% endtest %}
