-- Equivalent of stg_order_strm_outbound in the native Snowflake guide.
-- CUSTOMER_HK is re-derived here from O_CUSTKEY using the identical
-- hash recipe as stg_customer -- this is standard Data Vault practice
-- and is exactly what lets hub_customer and link_customer_order agree
-- on the same hash key without a join at staging time.

{{ config(materialized='view') }}

{%- set yaml_metadata -%}
source_model: 'base_orders'
hashed_columns:
  ORDER_HK: O_ORDERKEY
  CUSTOMER_HK: O_CUSTKEY
  CUSTOMER_ORDER_HK:
    - O_ORDERKEY
    - O_CUSTKEY
  ORDER_HASHDIFF:
    is_hashdiff: true
    columns:
      - O_ORDERSTATUS
      - O_TOTALPRICE
      - O_ORDERDATE
      - O_ORDERPRIORITY
      - O_CLERK
      - O_SHIPPRIORITY
      - O_COMMENT
{%- endset -%}

{% set metadata_dict = fromyaml(yaml_metadata) %}

{{ automate_dv.stage(include_source_columns=true,
                      source_model=metadata_dict["source_model"],
                      hashed_columns=metadata_dict["hashed_columns"],
                      derived_columns=none,
                      ranked_columns=none) }}
