-- Equivalent of bv_sat_customer in the native Snowflake guide: enriches
-- the latest customer satellite record with nation/region names.
-- Kept as a view for the same reason as the native guide -- no latency,
-- no extra storage, and it's cheap to change.

{{ config(materialized='view') }}

WITH current_sat AS (

    SELECT *
    FROM {{ ref('sat_customer_details') }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CUSTOMER_HK ORDER BY LOAD_DATETIME DESC
    ) = 1

)

SELECT
    cs.CUSTOMER_HK
  , cs.LOAD_DATETIME
  , cs.C_NAME
  , cs.C_ADDRESS
  , cs.C_PHONE
  , cs.C_ACCTBAL
  , cs.C_MKTSEGMENT
  , cs.C_COMMENT
  , cs.C_NATIONKEY
  , cs.RECORD_SOURCE
  -- derived
  , n.N_NAME   AS NATION_NAME
  , r.R_NAME   AS REGION_NAME
FROM current_sat cs
LEFT JOIN {{ ref('ref_nation') }} n ON cs.C_NATIONKEY = n.N_NATIONKEY
LEFT JOIN {{ ref('ref_region') }} r ON n.N_REGIONKEY  = r.R_REGIONKEY
