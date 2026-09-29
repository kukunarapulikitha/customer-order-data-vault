-- Hand-written equivalent of hub_customer (automate_dv.hub()).
-- One row per business key, stamped with the first time it was seen.
-- Insert-only: a key already in the hub is never touched again.

{{ config(materialized='incremental', incremental_strategy='append') }}

WITH staged AS (

    -- earliest record per key in this batch
    SELECT CUSTOMER_HK, C_CUSTKEY, LOAD_DATETIME, RECORD_SOURCE
    FROM {{ ref('stg_customer_native') }}
    WHERE CUSTOMER_HK IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY CUSTOMER_HK ORDER BY LOAD_DATETIME) = 1

)

SELECT s.CUSTOMER_HK, s.C_CUSTKEY, s.LOAD_DATETIME, s.RECORD_SOURCE
FROM staged s
{% if is_incremental() %}
WHERE NOT EXISTS (SELECT 1 FROM {{ this }} h WHERE h.CUSTOMER_HK = s.CUSTOMER_HK)
{% endif %}
