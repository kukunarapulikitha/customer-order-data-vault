-- Static Reference Data. Mirrors ref_nation in the native Snowflake guide --
-- this doesn't need hub/sat treatment since it's a fixed reference set,
-- not an entity we're tracking history for.

{{ config(materialized='table') }}

SELECT
    N_NATIONKEY
  , N_NAME
  , N_REGIONKEY
  , N_COMMENT
  , CURRENT_TIMESTAMP()   AS LOAD_DATETIME
  , 'STATIC_REFERENCE'    AS RECORD_SOURCE
FROM {{ source('tpch', 'nation') }}
