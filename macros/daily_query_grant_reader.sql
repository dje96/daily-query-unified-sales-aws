{#
  on-run-end: let the Content Analytics app's role (var daily_query_reader_role) read
  <DAILY_QUERY_DATABASE>.<schema>_DAILY_QUERY_DERIVED. Skipped when the run itself uses that role
  (local dev) or the schema does not exist yet. The reader role needs usage on the database (it owns
  SE_DEMO_DB).
#}
{% macro daily_query_grant_reader() %}
  {% if not execute %}{{ return('select 1') }}{% endif %}
  {% set reader = var('daily_query_reader_role') %}
  {% set db = env_var('DAILY_QUERY_DATABASE', 'SE_DEMO_DB') %}
  {% set derived = target.schema ~ '_daily_query_derived' %}
  {% if (target.role or '') | upper == reader | upper %}
    {{ return('select 1') }}
  {% endif %}
  {% if not adapter.check_schema_exists(db, derived) %}
    {{ log('daily_query_grant_reader: ' ~ derived ~ ' does not exist yet, skipping', info=true) }}
    {{ return('select 1') }}
  {% endif %}
  {% do run_query('grant usage on schema ' ~ db ~ '.' ~ derived ~ ' to role ' ~ reader) %}
  {{ return('grant select on all tables in schema ' ~ db ~ '.' ~ derived ~ ' to role ' ~ reader) }}
{% endmacro %}
