{#
  ONE-OFF RECOVERY. Delete this file once it has run.

  On 2026-11-20 at 16:15 PT this project's first Console run wrote into the shared
  ANALYTICS_DEV_DB.DBT_SALES_AWS_* schemas. That replaced five Snowplow Unified tables belonging to the
  Sales AWS Unified + Attribution model, and added Media Player tables there.
  This macro puts those schemas back as they were at 16:14:30 PT, before that run:
    1. Unified derived tables: move the replacement aside and UNDROP the original (Time Travel, 1 day).
    2. Unified and Attribution manifests, and Attribution tables: rewind to 16:14:30 PT. The Sales AWS
       model's next run then reprocesses everything since, so nothing is missing.
    3. Drop the replacements and the Media Player tables this project left there.

  Run from Console as the data modeling connection (DATAMODELING_ROLE), while the Sales AWS model is
  not running (it runs at about :02 past each hour; aim for :20 to :55):
    dbt deps
    dbt run-operation restore_dbt_sales_aws                            (dry run: logs the plan only)
    dbt run-operation restore_dbt_sales_aws --args '{dry_run: false}'  (does it)
  Safe to run twice: tables already restored are skipped.
#}
{% macro restore_dbt_sales_aws(dry_run=true) %}
  {% set db = 'ANALYTICS_DEV_DB' %}
  {% set derived = db ~ '.DBT_SALES_AWS_DERIVED' %}
  {% set manifest = db ~ '.DBT_SALES_AWS_SNOWPLOW_MANIFEST' %}
  {% set scratch = db ~ '.DBT_SALES_AWS_SCRATCH' %}
  {% set bad_run = '2026-11-20 16:15:00 -08:00' %}
  {% set before_bad_run = '2026-11-20 16:14:30 -08:00' %}
  {% set deadline = '2026-11-21 16:15:00 -08:00' %}
  {% set unified = ['SNOWPLOW_UNIFIED_USER_MAPPING', 'SNOWPLOW_UNIFIED_CONVERSIONS', 'SNOWPLOW_UNIFIED_VIEWS',
                    'SNOWPLOW_UNIFIED_SESSIONS', 'SNOWPLOW_UNIFIED_USERS'] %}
  {% set rewind = [
      manifest ~ '.SNOWPLOW_UNIFIED_INCREMENTAL_MANIFEST',
      manifest ~ '.SNOWPLOW_UNIFIED_BASE_SESSIONS_LIFECYCLE_MANIFEST',
      manifest ~ '.SNOWPLOW_UNIFIED_BASE_QUARANTINED_SESSIONS',
      manifest ~ '.SNOWPLOW_ATTRIBUTION_INCREMENTAL_MANIFEST',
      derived ~ '.SNOWPLOW_ATTRIBUTION_PATHS_TO_CONVERSION',
      derived ~ '.SNOWPLOW_ATTRIBUTION_CHANNEL_ATTRIBUTIONS',
      derived ~ '.SNOWPLOW_ATTRIBUTION_CAMPAIGN_ATTRIBUTIONS'] %}
  {% set leftovers = [
      derived ~ '.SNOWPLOW_MEDIA_PLAYER_BASE',
      derived ~ '.SNOWPLOW_MEDIA_PLAYER_MEDIA_STATS',
      derived ~ '.SNOWPLOW_MEDIA_PLAYER_PLAYS_BY_PAGEVIEW',
      scratch ~ '.SNOWPLOW_MEDIA_PLAYER_BASE_EVENTS_THIS_RUN',
      scratch ~ '.SNOWPLOW_MEDIA_PLAYER_BASE_NEW_EVENT_LIMITS',
      scratch ~ '.SNOWPLOW_MEDIA_PLAYER_BASE_SESSIONS_THIS_RUN',
      scratch ~ '.SNOWPLOW_MEDIA_PLAYER_BASE_THIS_RUN',
      scratch ~ '.SNOWPLOW_MEDIA_PLAYER_PIVOT_BASE',
      manifest ~ '.SNOWPLOW_MEDIA_PLAYER_BASE_QUARANTINED_SESSIONS',
      manifest ~ '.SNOWPLOW_MEDIA_PLAYER_BASE_SESSIONS_LIFECYCLE_MANIFEST',
      manifest ~ '.SNOWPLOW_MEDIA_PLAYER_INCREMENTAL_MANIFEST'] %}

  {{ log('restore_dbt_sales_aws: ' ~ ('DRY RUN, nothing will change' if dry_run else 'RESTORING'), info=true) }}

  {% set check = run_query("select current_role(), current_timestamp() < '" ~ deadline ~ "'::timestamp_tz") %}
  {{ log('Role: ' ~ check.rows[0][0], info=true) }}
  {% if not check.rows[0][1] %}
    {{ exceptions.raise_compiler_error('Past the Time Travel deadline (' ~ deadline ~ '): the originals are gone.') }}
  {% endif %}

  {# 1. Which Unified tables are still the replacements created by the bad run? #}
  {% set current = run_query(
      "select table_name, created >= '" ~ bad_run ~ "'::timestamp_tz as is_replacement, row_count
       from " ~ db ~ ".information_schema.tables
       where table_schema = 'DBT_SALES_AWS_DERIVED' and table_name in ('" ~ unified | join("','") ~ "')") %}
  {% set to_restore = [] %}
  {% for row in current.rows %}
    {{ log('  ' ~ row[0] ~ ': ' ~ ('replacement, ' ~ row[2] ~ ' rows -> restore original' if row[1] else 'original already in place, skip'), info=true) }}
    {% if row[1] %}{% do to_restore.append(row[0]) %}{% endif %}
  {% endfor %}

  {% set statements = [] %}
  {% for t in to_restore %}
    {% do statements.append('drop table if exists ' ~ derived ~ '.' ~ t ~ '_DQ_BAD') %}
    {% do statements.append('alter table ' ~ derived ~ '.' ~ t ~ ' rename to ' ~ derived ~ '.' ~ t ~ '_DQ_BAD') %}
    {% do statements.append('undrop table ' ~ derived ~ '.' ~ t) %}
  {% endfor %}

  {# 2. Rewind, only when this call restores tables (a second call must not rewind newer runs). #}
  {% if to_restore %}
    {% for t in rewind %}
      {% do statements.append('insert overwrite into ' ~ t ~ ' select * from ' ~ t ~ " at(timestamp => '" ~ before_bad_run ~ "'::timestamp_tz)") %}
    {% endfor %}
  {% endif %}

  {% for s in statements %}
    {{ log(('  would run: ' if dry_run else '  running: ') ~ s, info=true) }}
    {% if not dry_run %}{% do run_query(s) %}{% endif %}
  {% endfor %}

  {% if dry_run %}
    {% for t in leftovers %}{{ log('  would run: drop table if exists ' ~ t, info=true) }}{% endfor %}
    {% for t in to_restore %}{{ log('  would run: drop table if exists ' ~ derived ~ '.' ~ t ~ '_DQ_BAD', info=true) }}{% endfor %}
    {{ log('Dry run done. Rerun with --args ' ~ "'{dry_run: false}'" ~ ' to apply.', info=true) }}
    {{ return('') }}
  {% endif %}

  {# Check the originals are back before dropping anything. #}
  {% set after = run_query(
      "select table_name, created < '2026-01-01'::timestamp_tz as is_original, row_count
       from " ~ db ~ ".information_schema.tables
       where table_schema = 'DBT_SALES_AWS_DERIVED' and table_name in ('" ~ unified | join("','") ~ "')") %}
  {% for row in after.rows %}
    {{ log('  ' ~ row[0] ~ ': ' ~ row[2] ~ ' rows, ' ~ ('original' if row[1] else 'NOT the original'), info=true) }}
    {% if not row[1] %}
      {{ exceptions.raise_compiler_error(row[0] ~ ' is not the original after UNDROP. Stopping before any drops; the *_DQ_BAD tables are kept.') }}
    {% endif %}
  {% endfor %}

  {# 3. Clean up. #}
  {% for t in to_restore %}{% do leftovers.append(derived ~ '.' ~ t ~ '_DQ_BAD') %}{% endfor %}
  {% for t in leftovers %}
    {{ log('  running: drop table if exists ' ~ t, info=true) }}
    {% do run_query('drop table if exists ' ~ t) %}
  {% endfor %}

  {% set m = run_query("select max(last_success) from " ~ manifest ~ ".SNOWPLOW_UNIFIED_INCREMENTAL_MANIFEST") %}
  {{ log('Done. Unified manifest last_success is ' ~ m.rows[0][0] ~ ' UTC; the next Sales AWS run picks up from there.', info=true) }}
{% endmacro %}
