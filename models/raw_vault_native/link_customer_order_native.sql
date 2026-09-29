-- Hand-written equivalent of link_customer_order (automate_dv.link()).
-- One row per customer/order relationship. Insert-only.

{{ config(materialized='incremental', incremental_strategy='append') }}

WITH staged AS (

    SELECT CUSTOMER_ORDER_HK, CUSTOMER_HK, ORDER_HK, LOAD_DATETIME, RECORD_SOURCE
    FROM {{ ref('stg_orders_native') }}
    WHERE CUSTOMER_ORDER_HK IS NOT NULL
      AND CUSTOMER_HK IS NOT NULL
      AND ORDER_HK IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY CUSTOMER_ORDER_HK ORDER BY LOAD_DATETIME) = 1

)

SELECT s.CUSTOMER_ORDER_HK, s.CUSTOMER_HK, s.ORDER_HK, s.LOAD_DATETIME, s.RECORD_SOURCE
FROM staged s
{% if is_incremental() %}
WHERE NOT EXISTS (SELECT 1 FROM {{ this }} l WHERE l.CUSTOMER_ORDER_HK = s.CUSTOMER_ORDER_HK)
{% endif %}
