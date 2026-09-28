-- Adds Data Vault audit columns before stage() derives hashes.
--
-- target dev (default): batch simulation over the TPC-H sample data
-- (mirrors the native guide's LIMIT 10 -> full reload):
--   dbt run --vars '{customer_limit: 10}'   -> first 10 customers (default)
--   dbt run --vars '{customer_limit: 0}'    -> all customers (late-arriving data fix)
--
-- target lz: reads the Snowpipe-fed Landing Zone table. Every run sees whatever
-- has genuinely landed; LOAD_DATETIME / RECORD_SOURCE are the real ingestion
-- metadata (ldts / rsrc) rather than CURRENT_TIMESTAMP().

{{ config(materialized='view') }}

{% if target.name == 'lz' %}

-- Casts match SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.CUSTOMER so hashdiffs are
-- computed over the same text representation in both targets.
SELECT
    raw_json:C_CUSTKEY::NUMBER(38,0)     AS C_CUSTKEY
  , raw_json:C_NAME::VARCHAR(25)         AS C_NAME
  , raw_json:C_ADDRESS::VARCHAR(40)      AS C_ADDRESS
  , raw_json:C_NATIONKEY::NUMBER(38,0)   AS C_NATIONKEY
  , raw_json:C_PHONE::VARCHAR(15)        AS C_PHONE
  , raw_json:C_ACCTBAL::NUMBER(12,2)     AS C_ACCTBAL
  , raw_json:C_MKTSEGMENT::VARCHAR(10)   AS C_MKTSEGMENT
  , raw_json:C_COMMENT::VARCHAR(117)     AS C_COMMENT
  , ldts                                 AS LOAD_DATETIME
  , rsrc                                 AS RECORD_SOURCE
FROM {{ source('lz_customer', 'stg_customer') }}

{% else %}

{% set customer_limit = var('customer_limit', 10) %}

SELECT
    src.*
  , CURRENT_TIMESTAMP()   AS LOAD_DATETIME
  , 'CUSTOMER_SYSTEM'     AS RECORD_SOURCE
FROM {{ source('tpch', 'customer') }} src
{% if customer_limit | int > 0 %}
QUALIFY ROW_NUMBER() OVER (ORDER BY src.C_CUSTKEY) <= {{ customer_limit }}
{% endif %}

{% endif %}
