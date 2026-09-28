-- Equivalent of fct_customer_order in the native Snowflake guide.
-- A factless fact -- add measures here if/when needed.

{{ config(materialized='view') }}

SELECT
    hc.C_CUSTKEY               AS CUSTOMER_ID
  , ho.O_ORDERKEY               AS ORDER_ID
  , l.LOAD_DATETIME             AS EFFECTIVE_DTS
  , l.RECORD_SOURCE
FROM {{ ref('link_customer_order') }} l
JOIN {{ ref('hub_customer') }}        hc ON l.CUSTOMER_HK = hc.CUSTOMER_HK
JOIN {{ ref('hub_order') }}           ho ON l.ORDER_HK    = ho.ORDER_HK
