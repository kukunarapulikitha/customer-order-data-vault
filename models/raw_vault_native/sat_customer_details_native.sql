-- Hand-written equivalent of sat_customer_details (automate_dv.sat() with
-- apply_source_filter). Insert-only history of customer attributes: a row is
-- added only when the attributes (hashdiff) differ from the previous version.

{{ config(materialized='incremental', incremental_strategy='append') }}

WITH staged AS (

    SELECT CUSTOMER_HK, CUSTOMER_HASHDIFF,
           C_NAME, C_ADDRESS, C_NATIONKEY, C_PHONE, C_ACCTBAL, C_MKTSEGMENT, C_COMMENT,
           LOAD_DATETIME, RECORD_SOURCE
    FROM {{ ref('stg_customer_native') }}
    WHERE CUSTOMER_HK IS NOT NULL

),

{% if is_incremental() %}

-- latest stored version of each key
latest AS (

    SELECT CUSTOMER_HK, CUSTOMER_HASHDIFF, LOAD_DATETIME
    FROM {{ this }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY CUSTOMER_HK ORDER BY LOAD_DATETIME DESC) = 1

),

-- only rows newer than what is stored, so a stage that re-presents history
-- (the lz target) never re-inserts old versions
candidates AS (

    SELECT s.*, l.CUSTOMER_HASHDIFF AS STORED_HASHDIFF
    FROM staged s
    LEFT JOIN latest l ON s.CUSTOMER_HK = l.CUSTOMER_HK
    WHERE l.CUSTOMER_HK IS NULL
       OR s.LOAD_DATETIME > l.LOAD_DATETIME

),

{% else %}

candidates AS (

    SELECT s.*, NULL::BINARY(20) AS STORED_HASHDIFF
    FROM staged s

),

{% endif %}

-- keep a row only if it differs from the version before it: the previous
-- row in this batch, or else the latest stored row
changes AS (

    SELECT *
    FROM candidates
    QUALIFY CUSTOMER_HASHDIFF IS DISTINCT FROM COALESCE(
        LAG(CUSTOMER_HASHDIFF) OVER (PARTITION BY CUSTOMER_HK ORDER BY LOAD_DATETIME),
        STORED_HASHDIFF
    )

)

SELECT CUSTOMER_HK, CUSTOMER_HASHDIFF,
       C_NAME, C_ADDRESS, C_NATIONKEY, C_PHONE, C_ACCTBAL, C_MKTSEGMENT, C_COMMENT,
       LOAD_DATETIME, RECORD_SOURCE
FROM changes
