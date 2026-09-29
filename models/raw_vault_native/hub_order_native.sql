-- Hand-written equivalent of hub_order (automate_dv.hub()).

{{ config(materialized='incremental', incremental_strategy='append') }}

WITH staged AS (

    SELECT ORDER_HK, O_ORDERKEY, LOAD_DATETIME, RECORD_SOURCE
    FROM {{ ref('stg_orders_native') }}
    WHERE ORDER_HK IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ORDER_HK ORDER BY LOAD_DATETIME) = 1

)

SELECT s.ORDER_HK, s.O_ORDERKEY, s.LOAD_DATETIME, s.RECORD_SOURCE
FROM staged s
{% if is_incremental() %}
WHERE NOT EXISTS (SELECT 1 FROM {{ this }} h WHERE h.ORDER_HK = s.ORDER_HK)
{% endif %}
