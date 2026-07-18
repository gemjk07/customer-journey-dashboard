WITH event_base AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,

    FORMAT_DATE(
      '%Y-%m',
      PARSE_DATE('%Y%m%d', event_date)
    ) AS month,

    user_pseudo_id,
    event_name,
    event_timestamp,

    CONCAT(
      user_pseudo_id,
      '-',
      CAST(
        (
          SELECT value.int_value
          FROM UNNEST(event_params)
          WHERE key = 'ga_session_id'
        ) AS STRING
      )
    ) AS session_id,

    device.category AS device_category,

    traffic_source.source AS source,
    traffic_source.medium AS medium,

    ecommerce.purchase_revenue AS purchase_revenue

  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE
    _TABLE_SUFFIX BETWEEN '20201201' AND '20210131'
),

session_level AS (
  SELECT
    month,
    session_id,
    user_pseudo_id,

 
    ANY_VALUE(device_category) AS device_category,

    ANY_VALUE(source) AS source,
    ANY_VALUE(medium) AS medium,

    MAX(IF(event_name = 'session_start', 1, 0))
      AS reached_session_start,

    MAX(IF(event_name = 'view_item', 1, 0))
      AS reached_view_item,

    MAX(IF(event_name = 'add_to_cart', 1, 0))
      AS reached_add_to_cart,

    MAX(IF(event_name = 'begin_checkout', 1, 0))
      AS reached_begin_checkout,

    MAX(IF(event_name = 'purchase', 1, 0))
      AS reached_purchase,

    SUM(
      IF(
        event_name = 'purchase',
        COALESCE(purchase_revenue, 0),
        0
      )
    ) AS session_revenue

  FROM event_base

  WHERE session_id IS NOT NULL

  GROUP BY
    month,
    session_id,
    user_pseudo_id
),


session_enriched AS (
  SELECT
    *,

    CASE
      WHEN source = '(direct)'
        OR medium = '(none)'
        THEN 'Direct'

      WHEN medium = 'organic'
        THEN 'Organic Search'

      WHEN medium IN ('cpc', 'ppc', 'paidsearch')
        THEN 'Paid Search'

      WHEN medium = 'referral'
        THEN 'Referral'

      WHEN medium = 'email'
        THEN 'Email'

      WHEN source = '(data deleted)'
        OR medium = '(data deleted)'
        THEN 'Unknown / Deleted'

      WHEN source = '<Other>'
        OR medium = '<Other>'
        THEN 'Other'

      WHEN source IS NULL
        AND medium IS NULL
        THEN 'Unknown'

      ELSE 'Other'
    END AS acquisition_channel

  FROM session_level

  WHERE reached_session_start = 1
),

/* Overall Performance */
overall_performance AS (
  SELECT
    month,
    'Overall' AS segment_type,
    'All Users' AS segment_value,

    COUNT(DISTINCT session_id) AS sessions,

    COUNT(DISTINCT IF(
      reached_view_item = 1,
      session_id,
      NULL
    )) AS view_sessions,

    COUNT(DISTINCT IF(
      reached_add_to_cart = 1,
      session_id,
      NULL
    )) AS cart_sessions,

    COUNT(DISTINCT IF(
      reached_begin_checkout = 1,
      session_id,
      NULL
    )) AS checkout_sessions,

    COUNT(DISTINCT IF(
      reached_purchase = 1,
      session_id,
      NULL
    )) AS purchasing_sessions,

    SUM(session_revenue) AS revenue

  FROM session_enriched

  GROUP BY month
),

/* Performance by Device */
device_performance AS (
  SELECT
    month,
    'Device' AS segment_type,
    COALESCE(device_category, 'Unknown') AS segment_value,

    COUNT(DISTINCT session_id) AS sessions,

    COUNT(DISTINCT IF(
      reached_view_item = 1,
      session_id,
      NULL
    )) AS view_sessions,

    COUNT(DISTINCT IF(
      reached_add_to_cart = 1,
      session_id,
      NULL
    )) AS cart_sessions,

    COUNT(DISTINCT IF(
      reached_begin_checkout = 1,
      session_id,
      NULL
    )) AS checkout_sessions,

    COUNT(DISTINCT IF(
      reached_purchase = 1,
      session_id,
      NULL
    )) AS purchasing_sessions,

    SUM(session_revenue) AS revenue

  FROM session_enriched

  GROUP BY
    month,
    device_category
),

/* Performance by Channel */
channel_performance AS (
  SELECT
    month,
    'Channel' AS segment_type,
    acquisition_channel AS segment_value,

    COUNT(DISTINCT session_id) AS sessions,

    COUNT(DISTINCT IF(
      reached_view_item = 1,
      session_id,
      NULL
    )) AS view_sessions,

    COUNT(DISTINCT IF(
      reached_add_to_cart = 1,
      session_id,
      NULL
    )) AS cart_sessions,

    COUNT(DISTINCT IF(
      reached_begin_checkout = 1,
      session_id,
      NULL
    )) AS checkout_sessions,

    COUNT(DISTINCT IF(
      reached_purchase = 1,
      session_id,
      NULL
    )) AS purchasing_sessions,

    SUM(session_revenue) AS revenue

  FROM session_enriched

  GROUP BY
    month,
    acquisition_channel
),

combined AS (
  SELECT * FROM overall_performance

  UNION ALL

  SELECT * FROM device_performance

  UNION ALL

  SELECT * FROM channel_performance
)

SELECT
  month,
  segment_type,
  segment_value,

  sessions,
  view_sessions,
  cart_sessions,
  checkout_sessions,
  purchasing_sessions,
  revenue,

  /* Session Start → View Item */
  SAFE_DIVIDE(
    view_sessions,
    sessions
  ) AS session_to_view_rate,

  /* View Item → Add to Cart */
  SAFE_DIVIDE(
    cart_sessions,
    view_sessions
  ) AS view_to_cart_rate,

  /* Add to Cart → Begin Checkout */
  SAFE_DIVIDE(
    checkout_sessions,
    cart_sessions
  ) AS cart_to_checkout_rate,

  /* Begin Checkout → Purchase */
  SAFE_DIVIDE(
    purchasing_sessions,
    checkout_sessions
  ) AS checkout_to_purchase_rate,

  /* Purchase Sessions ÷ Total Sessions */
  SAFE_DIVIDE(
    purchasing_sessions,
    sessions
  ) AS session_cvr,

  SAFE_DIVIDE(
    revenue,
    purchasing_sessions
  ) AS revenue_per_purchasing_session,

  SAFE_DIVIDE(
    sessions,
    SUM(sessions) OVER (
      PARTITION BY month, segment_type
    )
  ) AS session_share,

  SAFE_DIVIDE(
    revenue,
    SUM(revenue) OVER (
      PARTITION BY month, segment_type
    )
  ) AS revenue_share

FROM combined

ORDER BY
  month,
  segment_type,
  sessions DESC;