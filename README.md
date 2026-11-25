# Daily Query: Content Analytics dbt project

Builds the tables behind the Content Analytics Snowflake app from the Daily Query demo site.

| | |
|---|---|
| Source | `SNOWPLOW_SALES_AWS_PROD1_DB.ATOMIC.EVENTS`, `app_id in ('demo_media_publishing_web', 'demo-media-publishing-web')` (the hyphenated one is the site's earlier app ID, Jan to Oct 2026) |
| Output (Console) | `SE_DEMO_DB.DBT_SALES_AWS_DAILY_QUERY_DERIVED`: point the app's `warehouse.snowflake.source` here |
| Output (local dev) | `SE_DEMO_DB.DEV_DAILY_QUERY_DERIVED` |
| Packages | `snowplow_unified` 1.0.1, `snowplow_media_player` 1.0.2 (pinned in `package-lock.yml`) |

There are no custom models. The project configures Snowplow's packages for Daily Query's own schemas.

> **Own schemas only.** The Console connection's schema (`DBT_SALES_AWS`) also hosts the Sales AWS
> Unified + Attribution model in `DBT_SALES_AWS_{DERIVED,SCRATCH,SNOWPLOW_MANIFEST}`. Same package,
> same table names, same incremental manifest: sharing those schemas replaces that model's tables
> (it happened on 2026-11-20). `dbt_project.yml` therefore sends every model and seed to
> `daily_query_*` schemas. Keep those overrides, and mirror any new package folder in them.
>
> **Own database too.** Everything is built in `SE_DEMO_DB` (`+database`, override with env var
> `DAILY_QUERY_DATABASE`), not the connection's `ANALYTICS_DEV_DB`. The app's role `SE_DEMO_ROLE` owns
> `SE_DEMO_DB`; giving it `ANALYTICS_DEV_DB` would need SECURITYADMIN.

## What it adds to the standard tables

| Table | Columns | From |
|---|---|---|
| `snowplow_unified_views` | `article_id`, `article_title`, `article_author`, `article_category`, `article_tags`, `article_image_url` | `iglu:com.demo.media/article` entity |
| `snowplow_unified_sessions` | `num_article_views`, `num_articles_viewed`, `num_articles_read`, `num_article_pings`, `num_categories_viewed`, `num_article_impressions` | `com.demo.media/article_interaction` and page pings |
| `snowplow_unified_users` | `lifetime_article_views`, `lifetime_articles_read`, `lifetime_article_pings`, `max_categories_in_session` | the session columns above |
| `snowplow_unified_conversions` | `subscribe` conversion | `com.demo.media/subscription_workflow`, step `confirm_payment` |
| every view and session | `default_channel_group` adds AI, Aggregator, Google Discover, Internal, Direct | `macros/channel_group_query.sql` |
| `snowplow_media_player_*` | plays, watch time, completion | media plugin (`media_player` v2, `media_session`) |

Known gaps in the Daily Query data: `article_tags` is always null (the article entity has no tags),
`article_image_url` is null until the site sends `image_url` (article 1-0-1, optional),
`cv_value` is 0 (the subscription event carries the plan, not revenue), and `num_article_impressions`
is 0 (only `view` interactions are tracked).

## Run it locally

Production runs come from Console (below). Locally, test into a dev schema only. Needs Python 3.10+
and a Snowflake user with key-pair auth that can read the events database and create schemas in
`SE_DEMO_DB`.

```bash
pip install -r requirements.txt
export SNOWFLAKE_ACCOUNT=yu83095.eu-west-1 SNOWFLAKE_USER=... SNOWFLAKE_PRIVATE_KEY="$(cat rsa_key.p8)"
dbt deps
dbt build    # into SE_DEMO_DB.DEV_DAILY_QUERY_*
```

Each run processes up to 365 days (`snowplow__backfill_limit_days`), so the first run covers the
whole history. Later runs only process new events. To rebuild from scratch:

```bash
dbt build --full-refresh --vars '{snowplow__allow_refresh: true}'
```

## Orchestrate

Scheduled from Snowplow Console (Sales AWS org), following
[Run data models from Console](https://docs.snowplow.io/docs/modeling-your-data/running-data-models-via-console/):

1. **Settings > Connections > Git repository**: connect this repo.
2. **Modeling > Model projects > Create model project**: "I already have a dbt project configured",
   Directory path empty (project at the repo root).
3. **Data modeling connection**: the Sales AWS one (`ANALYTICS_DEV_DB`, schema `DBT_SALES_AWS`,
   `DATAMODELING_ROLE`). Console overrides `profiles.yml` with it. Output goes to
   `SE_DEMO_DB.DBT_SALES_AWS_DAILY_QUERY_*`. After each run, an `on-run-end` hook grants the app's role
   (`daily_query_reader_role`, default `SE_DEMO_ROLE`) read access to the derived schema.
   One-time prerequisite, run as `SE_DEMO_ROLE`:
   `grant usage, create schema on database SE_DEMO_DB to role DATAMODELING_ROLE;`
4. **Add run configuration > Add schedule**: commands `dbt seed` then `dbt run` (Console runs
   `dbt deps` itself and only offers `run`, `seed`, `snapshot` and `test`).

Never run two builds of this project at once: Snowplow's incremental manifest expects one run at a
time.

## Change it

- Another site or app ID: `snowplow__app_id` in both package blocks of `dbt_project.yml`.
- Another events table: env vars `SNOWPLOW_EVENTS_DATABASE`, `SNOWPLOW_EVENTS_SCHEMA`, `SNOWPLOW_START_DATE`.
- Tracker activity tracking changed: keep `snowplow__heartbeat` / `snowplow__min_visit_length` equal to it.
- A new passthrough column is added by a normal `dbt run` (`on_schema_change: append_new_columns`), null for rows
  already processed. Backfilling it, or changing an existing passthrough, needs a full refresh (above; in Console,
  a one-off schedule with that command).
- The app depends on the column names above, so don't rename them.
