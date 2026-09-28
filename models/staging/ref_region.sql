{{ config(materialized='table') }}

SELECT
    R_REGIONKEY
  , R_NAME
  , R_COMMENT
  , CURRENT_TIMESTAMP()   AS LOAD_DATETIME
  , 'STATIC_REFERENCE'    AS RECORD_SOURCE
FROM {{ source('tpch', 'region') }}
