-- Hand-written equivalent of stg_customer (automate_dv.stage()).
-- Reads the same shared base model, so both vaults see identical input.

{{ config(materialized='view') }}

SELECT
    b.*
  , {{ dv_hash('C_CUSTKEY') }} AS CUSTOMER_HK
  , {{ dv_hash(['C_NAME', 'C_ADDRESS', 'C_NATIONKEY', 'C_PHONE',
                'C_ACCTBAL', 'C_MKTSEGMENT', 'C_COMMENT'], is_hashdiff=true) }} AS CUSTOMER_HASHDIFF
FROM {{ ref('base_customer') }} b
