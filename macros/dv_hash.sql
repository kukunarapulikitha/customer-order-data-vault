{#-
    Hand-written Data Vault hashing, used by the native (no-package) vault.

    Reproduces AutomateDV 0.11.5's compiled Snowflake SQL for this project's
    settings (hash: SHA1, concat_string: '^', null_placeholder_string: '-1'),
    so native hash keys and hashdiffs are byte-identical to the package's.
    The reconciliation tests in raw_vault_native.yml prove it.

      dv_hash('C_CUSTKEY')                         -- hash key, 1 column
      dv_hash(['O_ORDERKEY', 'O_CUSTKEY'])         -- hash key, composite
      dv_hash([...payload...], is_hashdiff=true)   -- hashdiff

    Rules (all per column): CAST to VARCHAR, TRIM, UPPER, '' -> NULL.
    - Single-column key: no placeholder, so a NULL key stays NULL and is
      filtered out by the hubs/links.
    - Composite key: NULL -> '-1', joined with '^'; all-NULL -> NULL.
    - Hashdiff: columns sorted alphabetically, NULL -> '-1', joined with '^'.
      Sorting means payload column order in the YAML never changes the hash.

    Compared with a naive md5(a || b || c):
    - The '^' delimiter stops ('1','23') and ('12','3') hashing the same.
    - The NULL placeholder stops one NULL column turning the whole hash NULL.
    - TRIM/UPPER stop cosmetic differences registering as changes.
-#}

{%- macro dv_hash(columns, is_hashdiff=false) -%}

{%- if var('hash', 'MD5') | upper != 'SHA1' -%}
    {{ exceptions.raise_compiler_error("dv_hash() only implements SHA1; vars.hash is '" ~ var('hash', 'MD5') ~ "'. Keep it in sync with AutomateDV.") }}
{%- endif -%}

{%- set cols = [columns] if columns is string else columns -%}
{%- set delim = var('concat_string') -%}
{%- set placeholder = var('null_placeholder_string') -%}

{%- if is_hashdiff -%}
    {%- set cols = cols | sort -%}
{%- endif -%}

{%- if cols | length == 1 and not is_hashdiff -%}

CAST(SHA1_BINARY(NULLIF(UPPER(TRIM(CAST({{ cols[0] }} AS VARCHAR))), '')) AS BINARY(20))

{%- else -%}

    {%- set parts = [] -%}
    {%- for col in cols -%}
        {%- do parts.append("IFNULL(NULLIF(UPPER(TRIM(CAST(" ~ col ~ " AS VARCHAR))), ''), '" ~ placeholder ~ "')") -%}
    {%- endfor -%}
    {%- set concatenated = "CONCAT_WS('" ~ delim ~ "', " ~ parts | join(", ") ~ ")" -%}

    {%- if is_hashdiff -%}
CAST(SHA1_BINARY({{ concatenated }}) AS BINARY(20))
    {%- else -%}
        {%- set all_null = ([placeholder] * (cols | length)) | join(delim) -%}
CAST(SHA1_BINARY(NULLIF({{ concatenated }}, '{{ all_null }}')) AS BINARY(20))
    {%- endif -%}

{%- endif -%}

{%- endmacro -%}
