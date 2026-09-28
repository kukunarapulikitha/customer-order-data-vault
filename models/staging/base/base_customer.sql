-- Adds Data Vault audit columns before stage() derives hashes.
-- Batch simulation (mirrors the native guide's LIMIT 10 -> full reload):
--   dbt run --vars '{customer_limit: 10}'   -> first 10 customers (default)
--   dbt run --vars '{customer_limit: 0}'    -> all customers (late-arriving data fix)

{{ config(materialized='view') }}

{% set customer_limit = var('customer_limit', 10) %}

SELECT
    src.*
  , CURRENT_TIMESTAMP()   AS LOAD_DATETIME
  , 'CUSTOMER_SYSTEM'     AS RECORD_SOURCE
FROM {{ source('tpch', 'customer') }} src
{% if customer_limit | int > 0 %}
QUALIFY ROW_NUMBER() OVER (ORDER BY src.C_CUSTKEY) <= {{ customer_limit }}
{% endif %}
