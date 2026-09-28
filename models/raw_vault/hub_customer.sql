-- Equivalent of rv_hub_customer in the native Snowflake guide.
-- One row per unique customer business key.

{{ config(materialized='incremental') }}

{%- set yaml_metadata -%}
source_model: 'stg_customer'
src_pk: CUSTOMER_HK
src_nk: C_CUSTKEY
src_ldts: LOAD_DATETIME
src_source: RECORD_SOURCE
{%- endset -%}

{% set metadata_dict = fromyaml(yaml_metadata) %}

{{ automate_dv.hub(src_pk=metadata_dict["src_pk"],
                    src_nk=metadata_dict["src_nk"],
                    src_ldts=metadata_dict["src_ldts"],
                    src_source=metadata_dict["src_source"],
                    source_model=metadata_dict["source_model"]) }}
