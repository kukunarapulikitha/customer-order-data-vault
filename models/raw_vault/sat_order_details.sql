-- Equivalent of rv_sat_order in the native Snowflake guide.

{{ config(materialized='incremental') }}

{%- set yaml_metadata -%}
source_model: 'stg_orders'
src_pk: ORDER_HK
src_hashdiff: ORDER_HASHDIFF
src_payload:
  - O_ORDERSTATUS
  - O_TOTALPRICE
  - O_ORDERDATE
  - O_ORDERPRIORITY
  - O_CLERK
  - O_SHIPPRIORITY
  - O_COMMENT
src_ldts: LOAD_DATETIME
src_source: RECORD_SOURCE
{%- endset -%}

{% set metadata_dict = fromyaml(yaml_metadata) %}

{{ automate_dv.sat(src_pk=metadata_dict["src_pk"],
                    src_hashdiff=metadata_dict["src_hashdiff"],
                    src_payload=metadata_dict["src_payload"],
                    src_ldts=metadata_dict["src_ldts"],
                    src_source=metadata_dict["src_source"],
                    source_model=metadata_dict["source_model"]) }}
