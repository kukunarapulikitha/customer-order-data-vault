-- Hand-written equivalent of stg_orders (automate_dv.stage()).
-- CUSTOMER_HK uses the same recipe as stg_customer_native, which is what lets
-- the link and the customer hub agree on keys without a join.

{{ config(materialized='view') }}

SELECT
    b.*
  , {{ dv_hash('O_ORDERKEY') }}                  AS ORDER_HK
  , {{ dv_hash('O_CUSTKEY') }}                   AS CUSTOMER_HK
  , {{ dv_hash(['O_ORDERKEY', 'O_CUSTKEY']) }}   AS CUSTOMER_ORDER_HK
  , {{ dv_hash(['O_ORDERSTATUS', 'O_TOTALPRICE', 'O_ORDERDATE', 'O_ORDERPRIORITY',
                'O_CLERK', 'O_SHIPPRIORITY', 'O_COMMENT'], is_hashdiff=true) }} AS ORDER_HASHDIFF
FROM {{ ref('base_orders') }} b
