{#
  on-run-end: let the Content Analytics app's role (var daily_query_reader_role) read
  <schema>_DAILY_QUERY_DERIVED. Skipped when the run itself uses that role (local dev) or the schema
  does not exist yet. One-time admin prerequisite: grant usage on database <db> to role <reader role>.
#}
{% macro daily_query_grant_reader() %}
  {% if not execute %}{{ return('select 1') }}{% endif %}
  {% set reader = var('daily_query_reader_role') %}
  {% set derived = target.schema ~ '_daily_query_derived' %}
  {% if (target.role or '') | upper == reader | upper %}
    {{ return('select 1') }}
  {% endif %}
  {% if not adapter.check_schema_exists(target.database, derived) %}
    {{ log('daily_query_grant_reader: ' ~ derived ~ ' does not exist yet, skipping', info=true) }}
    {{ return('select 1') }}
  {% endif %}
  {% do run_query('grant usage on schema ' ~ target.database ~ '.' ~ derived ~ ' to role ' ~ reader) %}
  {{ return('grant select on all tables in schema ' ~ target.database ~ '.' ~ derived ~ ' to role ' ~ reader) }}
{% endmacro %}
