-- Batch simulation (mirrors the native guide's LIMIT 1000 / OFFSET 1000):
--   dbt run --vars '{order_batch: 1}'  -> orders 1..1000 (default)
--   dbt run --vars '{order_batch: 2}'  -> orders 1001..2000
--   order_batch_size defaults to 1000

{{ config(materialized='view') }}

{% set batch = var('order_batch', 1) | int %}
{% set size  = var('order_batch_size', 1000) | int %}

SELECT
    src.*
  , CURRENT_TIMESTAMP()   AS LOAD_DATETIME
  , 'ORDERS_SYSTEM'       AS RECORD_SOURCE
FROM {{ source('tpch', 'orders') }} src
QUALIFY ROW_NUMBER() OVER (ORDER BY src.O_ORDERKEY)
        BETWEEN {{ (batch - 1) * size + 1 }} AND {{ batch * size }}
