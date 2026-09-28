-- Equivalent of bv_sat_order in the native Snowflake guide: the same
-- Urgent/High/Medium + totalprice tier-bucket soft rule, but as a plain
-- incremental dbt model instead of a hand-written Stream+Task chain.
-- dbt's incremental materialization is the batch-oriented analogue of
-- "AFTER stg_order_strm_tsk" in the native guide -- it processes only
-- rows newer than what's already loaded, on every dbt run.

{{ config(materialized='incremental', incremental_strategy='append') }}

SELECT
    ORDER_HK
  , LOAD_DATETIME
  , O_ORDERSTATUS
  , O_TOTALPRICE
  , O_ORDERDATE
  , O_ORDERPRIORITY
  , O_CLERK
  , O_SHIPPRIORITY
  , O_COMMENT
  , ORDER_HASHDIFF
  , RECORD_SOURCE
  -- derived additional attribute
  , CASE
        WHEN O_ORDERPRIORITY IN ('2-HIGH', '1-URGENT')
             AND O_TOTALPRICE >= 200000
            THEN 'Tier-1'
        WHEN O_ORDERPRIORITY IN ('3-MEDIUM', '2-HIGH', '1-URGENT')
             AND O_TOTALPRICE BETWEEN 150000 AND 200000
            THEN 'Tier-2'
        ELSE 'Tier-3'
    END AS ORDER_PRIORITY_BUCKET
FROM {{ ref('sat_order_details') }}

{% if is_incremental() %}
WHERE LOAD_DATETIME > (SELECT COALESCE(MAX(LOAD_DATETIME), '1900-01-01') FROM {{ this }})
{% endif %}
