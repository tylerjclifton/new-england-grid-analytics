{% macro generate_schema_name(custom_schema_name, node) -%}
  {#-
    Map each model's layer (+schema in dbt_project.yml) to a BigQuery dataset.

      gcp target (production)  → silver, gold
      any other target (local) → dev_silver, dev_gold

    So local builds never overwrite the live silver and gold. Sources aren't
    affected: both targets read the real bronze tables.
  -#}
  {%- if custom_schema_name is none -%}
    {{ target.schema }}
  {%- elif target.name == 'gcp' -%}
    {{ custom_schema_name | trim }}
  {%- else -%}
    dev_{{ custom_schema_name | trim }}
  {%- endif -%}
{%- endmacro %}
