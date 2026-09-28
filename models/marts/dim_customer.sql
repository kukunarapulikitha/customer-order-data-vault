-- Equivalent of dim1_customer in the native Snowflake guide.

{{ config(materialized='view') }}

SELECT
    h.C_CUSTKEY                AS CUSTOMER_ID
  , s.C_NAME
  , s.C_ADDRESS
  , s.C_PHONE
  , s.C_ACCTBAL
  , s.C_MKTSEGMENT
  , s.C_COMMENT
  , s.NATION_NAME
  , s.REGION_NAME
  , s.LOAD_DATETIME            AS EFFECTIVE_DTS
  , s.RECORD_SOURCE
FROM {{ ref('hub_customer') }}    h
JOIN {{ ref('bv_sat_customer') }} s ON h.CUSTOMER_HK = s.CUSTOMER_HK
