-- Equivalent of dim1_order in the native Snowflake guide. Note this
-- reads the *current* row per order out of bv_sat_order, matching
-- rv_sat_order_current in the native guide.

{{ config(materialized='view') }}

WITH current_bv AS (

    SELECT *
    FROM {{ ref('bv_sat_order') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ORDER_HK ORDER BY LOAD_DATETIME DESC
    ) = 1

)

SELECT
    h.O_ORDERKEY                AS ORDER_ID
  , s.O_ORDERSTATUS
  , s.O_TOTALPRICE
  , s.O_ORDERDATE
  , s.O_ORDERPRIORITY
  , s.O_CLERK
  , s.O_SHIPPRIORITY
  , s.O_COMMENT
  , s.ORDER_PRIORITY_BUCKET
  , s.LOAD_DATETIME             AS EFFECTIVE_DTS
  , s.RECORD_SOURCE
FROM {{ ref('hub_order') }} h
JOIN current_bv             s ON h.ORDER_HK = s.ORDER_HK
