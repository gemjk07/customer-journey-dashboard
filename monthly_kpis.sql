WITH base AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    FORMAT_DATE(
      '%Y-%m',
      PARSE_DATE('%Y%m%d', event_date)
    ) AS month,

    user_pseudo_id,
    event_name,

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
    END AS channel,

    ecommerce.purchase_revenue AS purchase_revenue,

    ecommerce.transaction_id AS transaction_id

  FROM
    `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

  WHERE
    _TABLE_SUFFIX BETWEEN '20201201' AND '20210131'
),

daily_performance AS (dd
  SELECT
    event_date,
    month,
    channel,
    device_category,

    COUNT(
      DISTINCT IF(
        event_name = 'session_start',
        session_id,
        NULL
      )
    ) AS sessions,

    COUNT(
      DISTINCT IF(
        event_name = 'purchase',
        session_id,
        NULL
      )
    ) AS purchasing_sessions,

    COUNT(
      DISTINCT IF(
        event_name = 'purchase',
        transaction_id,
        NULL
      )
    ) AS orders,

    SUM(
      IF(
        event_name = 'purchase',
        purchase_revenue,
        0
      )
    ) AS revenue

  FROM base

  WHERE session_id IS NOT NULL

  GROUP BY
    event_date,
    month,
    channel,
    device_category
)

SELECT
  event_date,
  month,
  channel,
  device_category,
  sessions,
  purchasing_sessions,
  orders,
  revenue,

  SAFE_DIVIDE(
    purchasing_sessions,
    sessions
  ) AS session_cvr,

  SAFE_DIVIDE(
    revenue,
    orders
  ) AS aov

FROM daily_performance

ORDER BY
  event_date,
  channel,
  device_category;