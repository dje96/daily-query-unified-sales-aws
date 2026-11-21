{#
  ONE-OFF RECOVERY (see macros/restore_dbt_sales_aws.sql). Delete with that macro once it has run.
  Applies the restore.
  Console only offers dbt run/seed/snapshot/test, so the restore runs through this model.
  It acts only when it is the ONLY model selected:
    dbt run --select restore_dbt_sales_aws_apply
  In any other run (a scheduled plain dbt run, for example) it does nothing.
#}
{{ config(materialized='view', schema='daily_query_scratch', tags=['ops']) }}

{% if execute %}
  {% if selected_resources == [model.unique_id] %}
    {% do restore_dbt_sales_aws(dry_run=false) %}
  {% else %}
    {{ log('restore_dbt_sales_aws_apply: not the only selected model, skipping', info=true) }}
  {% endif %}
{% endif %}

select 1 as placeholder
