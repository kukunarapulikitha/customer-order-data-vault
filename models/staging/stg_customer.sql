-- Equivalent of stg_customer_strm_outbound in the native Snowflake guide:
-- derives the hash key and hashdiff AutomateDV needs to build
-- hub_customer / sat_customer_details.

{{ config(materialized='view') }}

{%- set yaml_metadata -%}
source_model: 'base_customer'
hashed_columns:
  CUSTOMER_HK: C_CUSTKEY
  CUSTOMER_HASHDIFF:
    is_hashdiff: true
    columns:
      - C_NAME
      - C_ADDRESS
      - C_NATIONKEY
      - C_PHONE
      - C_ACCTBAL
      - C_MKTSEGMENT
      - C_COMMENT
{%- endset -%}

{% set metadata_dict = fromyaml(yaml_metadata) %}

{{ automate_dv.stage(include_source_columns=true,
                      source_model=metadata_dict["source_model"],
                      hashed_columns=metadata_dict["hashed_columns"],
                      derived_columns=none,
                      ranked_columns=none) }}
