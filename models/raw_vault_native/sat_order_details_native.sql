-- Hand-written equivalent of sat_order_details (automate_dv.sat() with
-- apply_source_filter). Same pattern as sat_customer_details_native.

{{ config(materialized='incremental', incremental_strategy='append') }}

WITH staged AS (

    SELECT ORDER_HK, ORDER_HASHDIFF,
           O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE, O_ORDERPRIORITY, O_CLERK, O_SHIPPRIORITY, O_COMMENT,
           LOAD_DATETIME, RECORD_SOURCE
    FROM {{ ref('stg_orders_native') }}
    WHERE ORDER_HK IS NOT NULL

),

{% if is_incremental() %}

latest AS (

    SELECT ORDER_HK, ORDER_HASHDIFF, LOAD_DATETIME
    FROM {{ this }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ORDER_HK ORDER BY LOAD_DATETIME DESC) = 1

),

candidates AS (

    SELECT s.*, l.ORDER_HASHDIFF AS STORED_HASHDIFF
    FROM staged s
    LEFT JOIN latest l ON s.ORDER_HK = l.ORDER_HK
    WHERE l.ORDER_HK IS NULL
       OR s.LOAD_DATETIME > l.LOAD_DATETIME

),

{% else %}

candidates AS (

    SELECT s.*, NULL::BINARY(20) AS STORED_HASHDIFF
    FROM staged s

),

{% endif %}

changes AS (

    SELECT *
    FROM candidates
    QUALIFY ORDER_HASHDIFF IS DISTINCT FROM COALESCE(
        LAG(ORDER_HASHDIFF) OVER (PARTITION BY ORDER_HK ORDER BY LOAD_DATETIME),
        STORED_HASHDIFF
    )

)

SELECT ORDER_HK, ORDER_HASHDIFF,
       O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE, O_ORDERPRIORITY, O_CLERK, O_SHIPPRIORITY, O_COMMENT,
       LOAD_DATETIME, RECORD_SOURCE
FROM changes
