-- target dev (default): batch simulation over the TPC-H sample data
-- (mirrors the native guide's LIMIT 1000 / OFFSET 1000):
--   dbt run --vars '{order_batch: 1}'  -> orders 1..1000 (default)
--   dbt run --vars '{order_batch: 2}'  -> orders 1001..2000
--   order_batch_size defaults to 1000
--
-- target lz: reads the Snowpipe-fed Landing Zone table (see base_customer.sql).

{{ config(materialized='view') }}

{% if target.name == 'lz' %}

-- Explicit columns so file lineage (filename, file_row_seq) stays out of the
-- stage. O_TOTALPRICE is cast back to the source's NUMBER(12,2); the LZ table
-- declares it NUMBER (scale 0), so cents are already rounded away on load.
SELECT
    O_ORDERKEY
  , O_CUSTKEY
  , O_ORDERSTATUS
  , O_TOTALPRICE::NUMBER(12,2)   AS O_TOTALPRICE
  , O_ORDERDATE
  , O_ORDERPRIORITY
  , O_CLERK
  , O_SHIPPRIORITY
  , O_COMMENT
  , ldts                         AS LOAD_DATETIME
  , rsrc                         AS RECORD_SOURCE
FROM {{ source('lz_orders', 'stg_orders') }}

{% else %}

{% set batch = var('order_batch', 1) | int %}
{% set size  = var('order_batch_size', 1000) | int %}

SELECT
    src.*
  , CURRENT_TIMESTAMP()   AS LOAD_DATETIME
  , 'ORDERS_SYSTEM'       AS RECORD_SOURCE
FROM {{ source('tpch', 'orders') }} src
QUALIFY ROW_NUMBER() OVER (ORDER BY src.O_ORDERKEY)
        BETWEEN {{ (batch - 1) * size + 1 }} AND {{ batch * size }}

{% endif %}
