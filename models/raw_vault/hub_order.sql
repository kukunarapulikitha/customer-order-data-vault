-- Equivalent of rv_hub_order in the native Snowflake guide.

{{ config(materialized='incremental') }}

{%- set yaml_metadata -%}
source_model: 'stg_orders'
src_pk: ORDER_HK
src_nk: O_ORDERKEY
src_ldts: LOAD_DATETIME
src_source: RECORD_SOURCE
{%- endset -%}

{% set metadata_dict = fromyaml(yaml_metadata) %}

{{ automate_dv.hub(src_pk=metadata_dict["src_pk"],
                    src_nk=metadata_dict["src_nk"],
                    src_ldts=metadata_dict["src_ldts"],
                    src_source=metadata_dict["src_source"],
                    source_model=metadata_dict["source_model"]) }}
