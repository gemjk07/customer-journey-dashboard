WITH base AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,

    FORMAT_DATE(
      '%Y-%m',
      PARSE_DATE('%Y%m%d', event_date)
    ) AS month,

    user_pseudo_id,
    event_name,

    device.category AS device_category,

    CASE
      WHEN traffic_source.medium = 'organic'
        THEN 'Organic Search'

      WHEN traffic_source.medium = 'cpc'
        THEN 'Paid Search'

      WHEN traffic_source.medium = 'referral'
        THEN 'Referral'

      WHEN traffic_source.source = '(direct)'
        OR traffic_source.medium = '(none)'
        THEN 'Direct'

      ELSE 'Other / Unknown'
    END AS channel

  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE
    _TABLE_SUFFIX BETWEEN '20201201' AND '20210131'

    AND event_name IN (
      'session_start',
      'view_item',
      'add_to_cart',
      'begin_checkout',
      'purchase'
    )
),

overall_funnel AS (
  SELECT
    event_date,
    month,
    'Overall' AS segment_type,
    'All Users' AS segment_value,
    event_name,
    COUNT(DISTINCT user_pseudo_id) AS users

  FROM base

  GROUP BY
    event_date,
    month,
    event_name
),

device_funnel AS (
  SELECT
    event_date,
    month,
    'Device' AS segment_type,
    COALESCE(device_category, 'Unknown') AS segment_value,
    event_name,
    COUNT(DISTINCT user_pseudo_id) AS users

  FROM base

  GROUP BY
    event_date,
    month,
    segment_value,
    event_name
),

channel_funnel AS (
  SELECT
    event_date,
    month,
    'Channel' AS segment_type,
    channel AS segment_value,
    event_name,
    COUNT(DISTINCT user_pseudo_id) AS users

  FROM base

  GROUP BY
    event_date,
    month,
    channel,
    event_name
),

combined AS (
  SELECT * FROM overall_funnel
  UNION ALL
  SELECT * FROM device_funnel
  UNION ALL
  SELECT * FROM channel_funnel
)

SELECT
  event_date,
  month,
  segment_type,
  segment_value,

  CASE event_name
    WHEN 'session_start' THEN 'Session Start'
    WHEN 'view_item' THEN 'View Item'
    WHEN 'add_to_cart' THEN 'Add to Cart'
    WHEN 'begin_checkout' THEN 'Begin Checkout'
    WHEN 'purchase' THEN 'Purchase'
  END AS stage,

  CASE event_name
    WHEN 'session_start' THEN 1
    WHEN 'view_item' THEN 2
    WHEN 'add_to_cart' THEN 3
    WHEN 'begin_checkout' THEN 4
    WHEN 'purchase' THEN 5
  END AS step_order,

  users

FROM combined

ORDER BY
  event_date,
  segment_type,
  segment_value,
  step_order;
