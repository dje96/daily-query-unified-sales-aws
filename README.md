# Daily Query: Content Analytics dbt project

Builds the tables behind the Content Analytics Snowflake app from the Daily Query demo site.

| | |
|---|---|
| Source | `SNOWPLOW_SALES_AWS_PROD1_DB.ATOMIC.EVENTS`, `app_id = 'demo_media_publishing_web'` |
| Output (prod) | `SE_DEMO_DB.CONTENT_ANALYTICS_DERIVED`, the schema the app reads |
| Output (dev) | `SE_DEMO_DB.DAILY_QUERY_DEV_DERIVED` |
| Packages | `snowplow_unified` 1.0.1, `snowplow_media_player` 1.0.2 (pinned in `package-lock.yml`) |

There are no custom models. The project configures Snowplow's packages for Daily Query's own schemas.

## What it adds to the standard tables

| Table | Columns | From |
|---|---|---|
| `snowplow_unified_views` | `article_id`, `article_title`, `article_author`, `article_category`, `article_tags` | `iglu:com.demo.media/article` entity |
| `snowplow_unified_sessions` | `num_article_views`, `num_articles_viewed`, `num_articles_read`, `num_article_pings`, `num_categories_viewed`, `num_article_impressions` | `com.demo.media/article_interaction` and page pings |
| `snowplow_unified_users` | `lifetime_article_views`, `lifetime_articles_read`, `lifetime_article_pings`, `max_categories_in_session` | the session columns above |
| `snowplow_unified_conversions` | `subscribe` conversion | `com.demo.media/subscription_workflow`, step `confirm_payment` |
| every view and session | `default_channel_group` adds AI, Aggregator, Google Discover, Internal, Direct | `macros/channel_group_query.sql` |
| `snowplow_media_player_*` | plays, watch time, completion | media plugin (`media_player` v2, `media_session`) |

Known gaps in the Daily Query data: `article_tags` is always null (the article entity has no tags),
`cv_value` is 0 (the subscription event carries the plan, not revenue), and `num_article_impressions`
is 0 (only `view` interactions are tracked).

## Run it

Needs Python 3.10+ and a Snowflake user with key-pair auth that can read the events database and
create schemas in `SE_DEMO_DB`.

```bash
pip install -r requirements.txt
export SNOWFLAKE_ACCOUNT=yu83095.eu-west-1 SNOWFLAKE_USER=... SNOWFLAKE_PRIVATE_KEY="$(cat rsa_key.p8)"
dbt deps
dbt build --target dev     # into DAILY_QUERY_DEV_*; check it first
dbt build --target prod    # into CONTENT_ANALYTICS_*; what the app reads
```

Each run processes up to 180 days (`snowplow__backfill_limit_days`), so the first run covers the
whole history. Later runs only process new events.

### First prod run: rebuild

The prod tables already exist, built by an earlier project that also read the `demo-media-publishing-web`
app ID. Rebuild them once so they hold only this project's data:

```bash
dbt build --target prod --full-refresh --vars '{snowplow__allow_refresh: true}'
```

The dashboards show nothing while the rebuild runs (a few minutes).

## Orchestrate

Scheduled from Snowplow Console (Sales AWS org), following
[Run data models from Console](https://docs.snowplow.io/docs/modeling-your-data/running-data-models-via-console/):

1. **Settings > Connections > Git repository**: connect this repo.
2. **Modeling > Model projects > Create model project**: point it at the repo root.
3. **Settings > Connections > Data modeling**: Snowflake, database `SE_DEMO_DB`, schema `CONTENT_ANALYTICS`,
   a role that reads `SNOWPLOW_SALES_AWS_PROD1_DB.ATOMIC` and owns the `CONTENT_ANALYTICS_*` schemas.
   Console overrides `profiles.yml` with this connection.
4. **Add run configuration > Add schedule**: hourly, commands `dbt deps` then `dbt build`.

Never run two builds at once (for example Console plus a local prod run): Snowplow's incremental
manifest expects one run at a time.

## Change it

- Another site or app ID: `snowplow__app_id` in both package blocks of `dbt_project.yml`.
- Another events table: env vars `SNOWPLOW_EVENTS_DATABASE`, `SNOWPLOW_EVENTS_SCHEMA`, `SNOWPLOW_START_DATE`.
- Tracker activity tracking changed: keep `snowplow__heartbeat` / `snowplow__min_visit_length` equal to it.
- New columns or changed passthroughs need a full refresh (above).
- The app depends on the column names above, so don't rename them.
