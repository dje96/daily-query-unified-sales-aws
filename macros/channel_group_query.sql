{#
  Publishing channel grouping for Daily Query. Overrides snowplow_unified.channel_group_query
  (see dispatch in dbt_project.yml). Publisher rules run first; everything else falls through to
  Unified's default grouping.
    AI              chat assistants
    Aggregator      news aggregators
    Google Discover Android Google app
    Internal        referer enrichment marked the referrer as one of our own domains
    Direct          no referrer and no UTM parameters
#}
{% macro snowflake__channel_group_query() %}
case
   when lower(refr_urlhost) rlike '.*(chatgpt\\.com|chat\\.openai\\.com|perplexity\\.ai|gemini\\.google\\.com|copilot\\.microsoft\\.com|claude\\.ai).*' then 'AI'
   when lower(refr_urlhost) rlike '.*(news\\.google\\.com|flipboard\\.com|smartnews\\.com|newsbreak\\.com|msn\\.com|news\\.yahoo\\.com|apple\\.news).*' then 'Aggregator'
   when lower(refr_urlhost) = 'com.google.android.googlequicksearchbox' or lower(page_referrer) like 'android-app://com.google.android.googlequicksearchbox%' then 'Google Discover'
   when refr_medium = 'internal' and mkt_medium is null and mkt_source is null then 'Internal'
   else coalesce(nullif({{ snowplow_unified.default__channel_group_query() }}, 'Unassigned'),
                 case when refr_urlhost is null and page_referrer is null and mkt_medium is null and mkt_source is null then 'Direct' end,
                 'Unassigned')
end
{% endmacro %}
