# TPC-H Data Vault 2.0 on dbt Core + Snowflake

A dbt Core rebuild of the TPC-H customer/order Data Vault from Snowflake's two
native guides:

- [Defensible Analytics using Data Vault and Snowflake](https://www.snowflake.com/en/developers/guides/defensible-analytics-using-data-vault-and-snowflake/)
- [Building a Real-Time Data Vault in Snowflake](https://www.snowflake.com/en/developers/guides/vhol-data-vault/)

The raw vault is built **twice, side by side**, and the two are proven
identical by tests:

1. with [AutomateDV](https://automate-dv.readthedocs.io/) (formerly `dbtvault`),
   the most widely used open-source dbt package for Data Vault 2.0, and
2. by hand, in plain dbt SQL plus one hashing macro — no package.

It can be fed two ways: a vars-driven batch simulation over Snowflake's sample
data (`dev` target, zero setup), or the native guide's Snowpipe-fed Landing
Zone tables (`lz` target), where each run picks up rows that have genuinely
landed.

**Stack:** dbt Core 1.12 · dbt-snowflake 1.12 · AutomateDV 0.11.5 · dbt_utils 1.4 · Snowflake · Python 3.12

## Architecture

| Layer | Snowflake database | Schemas (`dev` / `lz` target) | Models |
|---|---|---|---|
| Source | `SNOWFLAKE_SAMPLE_DATA` / `DEV_LZ` | `TPCH_SF1` / `TPCH_CUSTOMER_SYS`, `TPCH_ORDERS_SYS` | read-only |
| Staging | `DBT_STAGING` | `dev_staging` / `dev_lz_staging` | `base_*`, `stg_*`, `stg_*_native`, `ref_nation`, `ref_region` |
| Raw vault | `DBT_DATA_VAULT` | `dev_raw_vault` / `dev_lz_raw_vault` | hubs, link, satellites (AutomateDV) |
| Raw vault (native) | `DBT_DATA_VAULT` | `dev_raw_vault_native` / `dev_lz_raw_vault_native` | same tables, hand-written |
| Business vault | `DBT_DATA_VAULT` | `dev_business_vault` / `dev_lz_business_vault` | `bv_sat_customer`, `bv_sat_order`, `as_of_dates`, `pit_customer` |
| Information marts | `DBT_WAREHOUSE` | `dev_marts` / `dev_lz_marts` | `dim_customer`, `dim_order`, `fct_customer_order` |

One database per layer mirrors the native guide's `DEV_LZ` / `DEV_DV` /
`DEV_DW` split. The two targets write to separate schemas, so their
incremental tables never mix.

<!-- TODO: lineage screenshot. Run `dbt docs generate --target lz && dbt docs serve`,
     open the lineage graph, and save it as docs/lineage.png -->
<!-- ![Lineage graph](docs/lineage.png) -->

## Read this first: dbt vs. the native guide

The native Snowflake guide gets its "real-time" behaviour from **Snowpipe +
Streams + Tasks running inside Snowflake, continuously**. dbt does not do
that. dbt is a transformation tool: it compiles Jinja + SQL into
`CREATE TABLE/VIEW` / `INSERT` statements and runs them **when you tell it
to** — a manual `dbt build`, a scheduled job, or a step in an orchestrator.

So this project replaces the *SQL* in `DVRealTime.sql` (the hub/link/sat DDL
and the multi-table-insert task bodies), not the Snowpipe layer that feeds it.
With the `lz` target, Snowpipe keeps landing files into the Landing Zone and
dbt, run on a schedule, loads whatever is new.

## How the pieces map

| Native Snowflake guide | This dbt project | Mechanism |
|---|---|---|
| `stg_customer_strm_outbound` / `stg_order_strm_outbound` (views with `SHA1_BINARY()`) | `models/staging/stg_customer.sql`, `stg_orders.sql` | `automate_dv.stage()` |
| `rv_hub_customer`, `rv_hub_order` | `models/raw_vault/hub_customer.sql`, `hub_order.sql` | `automate_dv.hub()`, incremental |
| `rv_sat_customer`, `rv_sat_order` | `models/raw_vault/sat_customer_details.sql`, `sat_order_details.sql` | `automate_dv.sat()`, incremental |
| `rv_lnk_customer_order` | `models/raw_vault/link_customer_order.sql` | `automate_dv.link()`, incremental |
| (none — same vault, hand-written) | `models/raw_vault_native/*`, `macros/dv_hash.sql` | plain SQL, incremental append |
| `ref_nation`, `ref_region` | `models/staging/ref_nation.sql`, `ref_region.sql` | plain table models |
| `bv_sat_customer` (view) | `models/business_vault/bv_sat_customer.sql` | plain view, `QUALIFY` for current row |
| `bv_sat_order` (Stream+Task, tier-bucket rule) | `models/business_vault/bv_sat_order.sql` | incremental model, same `CASE` logic |
| (none) | `models/business_vault/as_of_dates.sql`, `pit_customer.sql` | date spine + point-in-time table |
| `dim1_customer`, `dim1_order` | `models/marts/dim_customer.sql`, `dim_order.sql` | views |
| `fct_customer_order` | `models/marts/fct_customer_order.sql` | view |
| Closing nation/region/tier query | `analyses/orders_by_region_tier.sql` | dbt analysis (`dbt show`) |
| Primary/foreign key `CONSTRAINT`s (unenforced by Snowflake) | `raw_vault.yml`, `raw_vault_native.yml`, `marts.yml`, `tests/` | real dbt tests that fail the build |

Hub hash keys are **byte-identical** to the guide's
`SHA1_BINARY(UPPER(TRIM(key)))`: 0 differences in either direction on 1.5M
customers and 3,000 orders (checked against the guide's recipe applied to the
Landing Zone). Hashdiffs differ by design — the guide concatenates with
`ARRAY_TO_STRING` in declared column order, AutomateDV with `CONCAT_WS('^')`
over alphabetically sorted columns — so don't mix the two projects' satellites.

## Setup

Needs Python 3.9–3.12 (dbt-snowflake doesn't support 3.13+ yet) and a
Snowflake account.

1. Environment (project-local; nothing installed globally):
   ```bash
   uv venv --python 3.12 .venv      # or: python3.12 -m venv .venv
   uv pip install --python .venv/bin/python -r requirements.txt
   ```
2. Credentials — a gitignored `.env` in the project root, never committed:
   ```bash
   SNOWFLAKE_ACCOUNT=ORGNAME-ACCOUNTNAME
   SNOWFLAKE_USER=...
   SNOWFLAKE_PASSWORD='...'
   # SNOWFLAKE_WAREHOUSE=COMPUTE_WH   (optional, this is the default)
   ```
3. Profile: `cp profiles.yml.example profiles.yml` (also gitignored; it only
   reads env vars). No role is set, so your user's default role is used.
4. Output databases, once, in Snowsight:
   ```sql
   CREATE DATABASE IF NOT EXISTS DBT_STAGING;
   CREATE DATABASE IF NOT EXISTS DBT_DATA_VAULT;
   CREATE DATABASE IF NOT EXISTS DBT_WAREHOUSE;
   ```
5. Run:
   ```bash
   set -a; source .env; set +a; export DBT_PROFILES_DIR=.
   .venv/bin/dbt deps
   .venv/bin/dbt debug
   .venv/bin/dbt build
   ```

## Two ways to feed the vault

The staging, vault and mart models are identical in both modes; only
`models/staging/base/base_customer.sql` / `base_orders.sql` switch on
`target.name`.

| | `dev` target (default) | `lz` target |
|---|---|---|
| Source | `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1` | `DEV_LZ.TPCH_CUSTOMER_SYS.stg_customer` (JSON), `DEV_LZ.TPCH_ORDERS_SYS.stg_orders` (CSV) — Snowpipe-fed |
| New data per run | Simulated with vars: `--vars '{order_batch: 2, customer_limit: 0}'` | Whatever Snowpipe has actually landed |
| LOAD_DATETIME / RECORD_SOURCE | `CURRENT_TIMESTAMP()` / constant | Real ingestion metadata: `ldts` / `rsrc` |
| Setup needed | None beyond the three output databases | DVArchitecture.sql + DVRealTime.sql Landing Zone steps |

```bash
dbt build                                                # dev: batch 1 (10 customers, orders 1–1000)
dbt run   --vars '{order_batch: 2}'                      # dev: next 1000 orders
dbt run   --vars '{order_batch: 2, customer_limit: 0}'   # dev: late-arriving customers
dbt build --target lz                                    # lz: load what has landed
dbt source freshness --target lz
```

Loading a new batch for the `lz` target (in Snowsight, then `dbt build --target lz`):

```sql
COPY INTO @DEV_LZ.TPCH_ORDERS_SYS.orders_data
FROM (SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS
      WHERE o_orderkey > <current max o_orderkey> ORDER BY o_orderkey LIMIT 1000)
INCLUDE_QUERY_ID = TRUE;
USE SCHEMA DEV_LZ.TPCH_ORDERS_SYS;      -- required, see "Issues found" below
ALTER PIPE stg_orders_pp REFRESH;
```

## Results

### `dev` target — simulated batches (AutomateDV and native vaults identical at every step)

| Step | hub_customer | hub_order | link | sat_customer | sat_order | bv_sat_order | fct_customer_order |
|---|---|---|---|---|---|---|---|
| 1. `dbt build` (10 customers, orders 1–1000) | 10 | 1,000 | 1,000 | 10 | 1,000 | 1,000 | 0 |
| 2. `--vars '{order_batch: 2}'` | 10 (+0) | 2,000 | 2,000 | 10 (+0) | 2,000 | 2,000 | 0 |
| 3. same batch again (idempotency) | 10 | 2,000 | 2,000 | 10 | 2,000 | 2,000 | 0 |
| 4. `--vars '{order_batch: 2, customer_limit: 0}'` | 150,000 | 2,000 | 2,000 | 150,000 | 2,000 | 2,000 | 2,000 |

- Step 1: the `relationships` test from the link to `hub_customer` **fails on
  1,000 rows**, by design. The first 1,000 orders belong to 997 customers,
  none of whom are among the first 10 loaded. This is the guide's
  late-arriving-data scenario, caught by a real test rather than an
  unenforced constraint. Step 4 loads the missing customers and the test passes.
- Step 2: all 10 customers are restaged with a new `CURRENT_TIMESTAMP()`, yet
  the hub and satellite insert 0 rows (known key, unchanged hashdiff).
- Step 3: every vault model inserts 0 rows.

### `lz` target — real Snowpipe loads

| Step | hub_customer | hub_order | link | sat_customer | sat_order | bv_sat_order |
|---|---|---|---|---|---|---|
| 1. Existing landing zone (1,500,010 customer rows, 2,000 orders) | 1,500,000 | 2,000 | 2,000 | 1,500,000 | 2,000 | 2,000 |
| 2. Re-run, nothing new landed | +0 | +0 | +0 | +0 | +0 | +0 |
| 3. Snowpipe lands 1,000 new orders + 5 changed customers (loaded twice → 10 rows) | 1,500,000 | 3,000 | 3,000 | **1,500,005** | 3,000 | 3,000 |
| 4. Re-run, nothing new landed | +0 | +0 | +0 | +0 | +0 | +0 |

- The guide loaded 10 customers twice; both vaults dedupe them (1,500,010 → 1,500,000).
- The 5 changed customers get a second satellite row but no new hub row;
  `dim_customer` shows the new address, and `pit_customer` points at the old
  version as of Sep 27 and the new one from Sep 28.
- The native vault, built in **one pass** over the same landing zone, matches
  the AutomateDV vault (built incrementally over several runs) row for row, LOAD_DATETIME included.

### Tests

46 data tests, all passing on both targets:

- PK/FK tests on both raw vaults (`unique`, `not_null`, `relationships`)
- mart tests (`unique`/`not_null` IDs, `accepted_values` on the tier bucket)
- `tests/assert_tier1_rule.sql` — Tier-1 must mean URGENT/HIGH and ≥ 200,000
- `tests/assert_sat_no_duplicate_hashdiff.sql` — no key + hashdiff stored twice
- 7 reconciliation tests (`dbt_utils.equality`, `EXCEPT` both ways):
  AutomateDV vault = hand-written vault, table by table
- PIT grain (`unique_combination_of_columns` on customer + as-of date)

## Two implementations of the same vault: AutomateDV vs. plain dbt SQL

| | AutomateDV (`models/raw_vault/`) | Hand-written (`models/raw_vault_native/`) |
|---|---|---|
| Hashing | `automate_dv.stage(hashed_columns=...)` | `dv_hash()` macro in `macros/dv_hash.sql` |
| Hubs / link | `automate_dv.hub()` / `link()` | `QUALIFY ROW_NUMBER()` for first-seen + `NOT EXISTS` against `{{ this }}` |
| Satellites | `automate_dv.sat()` with `apply_source_filter` | latest-stored-row join + `LAG` over hashdiff |
| Lines (non-comment) | 48 stage + 90 vault | 16 stage + 116 vault + 26 macro |

What the package hides, and the hand-written version has to get right:
- **Hashing rules** — `CAST → TRIM → UPPER → NULLIF('')`, a `-1` NULL placeholder,
  `^` delimiter, hashdiff columns **sorted alphabetically**, all-NULL composite
  keys → NULL. `dv_hash()` reproduces the compiled SQL character for character.
- **Satellite change detection against history.** Comparing only to the latest
  stored hashdiff is not enough when the stage re-presents old rows (the `lz`
  target reads the whole landing zone each run): the old version looks like a
  change and is re-inserted. Both vaults filter to rows newer than the latest
  stored `LOAD_DATETIME` per key — AutomateDV only does this with
  `apply_source_filter`, which is off by default.

Compared with the naive pattern in many tutorials (`md5(a || b || c)`,
full-rebuild satellites, `current_timestamp` as the hub load date), this
version: delimits hash inputs so `('1','23')` ≠ `('12','3')`; survives NULLs;
keeps history via insert-only incremental satellites; and stamps hubs with the
first time a key was seen, not the time of the latest run.

The PIT table is hand-written too: AutomateDV deprecated `pit()` / `bridge()`
in 0.11.0 as "not currently fit-for-purpose".

## Issues found along the way

| Issue | Symptom | Fix |
|---|---|---|
| AutomateDV vars nested under `vars: automate_dv:` | Silently ignored: hashes compiled to `MD5_BINARY` with `\|\|` instead of SHA1 with `^` | Top-level `vars:` — the package's macros run in the project's context |
| `sat()` without `apply_source_filter` on a stage that re-presents history | Dry run showed 10 old satellite versions would be re-inserted on every `lz` run | `meta={'apply_source_filter': true}` on both satellites (caught before any bad data landed) |
| Guide's pipes use an unqualified target (`COPY INTO stg_orders`) | `ALTER PIPE ... REFRESH` fails with "Table 'STG_ORDERS' does not exist" from another schema | `USE SCHEMA DEV_LZ.TPCH_ORDERS_SYS;` before the refresh |
| Guide's Landing Zone DDL declares `o_totalprice NUMBER` (scale 0) | Snowpipe rounds 1,978 of 2,000 prices to whole units | dbt casts back to `NUMBER(12,2)`; the cents are already lost upstream |
| Guide's unloads use `LIMIT n OFFSET m` without `ORDER BY` | Batches aren't deterministic and can overlap | Unload with `WHERE o_orderkey > max ORDER BY o_orderkey LIMIT 1000` |
| JSON paths are case-sensitive in Snowflake | `raw_json:c_custkey` is NULL; keys are `C_CUSTKEY` | Uppercase paths in `base_customer` |

## Where dbt genuinely improves on the hand-written SQL

- **No repeated hashing logic.** Written once — in the package, or in
  `dv_hash()` — not by hand in every model.
- **Real tests, not unenforced `CONSTRAINT`s.** Snowflake doesn't enforce
  PK/FK; `dbt test` fails the build on duplicate hub keys or orphaned links —
  and here it also proves two implementations equal.
- **Auto-generated docs and lineage.** `dbt docs generate && dbt docs serve`
  replaces the ERD the guide had to draw by hand.
- **One place to change the hashing algorithm or delimiter** — the top-level
  `vars:` in `dbt_project.yml`.
- **Idempotent re-runs.** Every incremental model can be re-run safely; the
  results tables above show +0 on every repeat.

## Where the native Snowflake guide still wins

- **True streaming ingestion.** Snowpipe + Streams process rows the moment
  they land; dbt only runs when invoked.
- **Multi-table insert in one transaction.** The guide's `INSERT ALL ... WHEN
  ... THEN INTO` loads hub + satellite + link atomically. dbt builds them as
  separate models — same result, but three statements, not one.
- **Zero extra tooling.** No `dbt deps`, no package pinning, no separate
  orchestration.

## Project layout

```
analyses/orders_by_region_tier.sql     guide's closing query over the marts
macros/dv_hash.sql                     hand-written hashing (= AutomateDV's)
models/
  staging/
    src_tpch.yml, src_lz.yml           sources (lz only enabled on --target lz)
    base/                              audit columns; switch on target.name
    stg_customer.sql, stg_orders.sql   automate_dv.stage()
    native/                            same hashes via dv_hash()
    ref_nation.sql, ref_region.sql     static reference data
  raw_vault/                           AutomateDV hubs, link, satellites
  raw_vault_native/                    hand-written equivalents + reconciliation tests
  business_vault/                      bv_sat_*, as_of_dates, pit_customer
  marts/                               dim_customer, dim_order, fct_customer_order
tests/                                 singular tests (tier rule, duplicate hashdiff)
```

## What I learned

<!-- For the author to write. -->
