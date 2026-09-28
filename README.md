# TPC-H Data Vault on dbt (AutomateDV)

This is a dbt implementation of the same TPC-H customer/order Data Vault
built in Snowflake's two native guides:

- [Defensible Analytics using Data Vault and Snowflake](https://www.snowflake.com/en/developers/guides/defensible-analytics-using-data-vault-and-snowflake/)
- [Building a Real-Time Data Vault in Snowflake](https://www.snowflake.com/en/developers/guides/vhol-data-vault/)

It uses [AutomateDV](https://automate-dv.readthedocs.io/) (formerly
`dbtvault`), the most widely used open-source dbt package for generating
Data Vault 2.0 ETL.

## Read this first: dbt vs. the native guide

The native Snowflake guide gets its "real-time" behavior from **Snowpipe +
Streams + Tasks running inside Snowflake, continuously, 24/7**. dbt does
not do that. dbt is a transformation tool: it compiles Jinja+SQL into
`CREATE TABLE/VIEW` statements and runs them **when you tell it to** (a
manual `dbt run`, a scheduled dbt Cloud job, or a step in an orchestrator
like Airflow/Dagster/a Snowflake Task calling out to dbt Cloud's API).

So this project is a like-for-like replacement for the *SQL* in
`DVRealTime.sql` (the hub/link/sat DDL and the multi-table-insert task
bodies) — not for the Snowpipe/Stream/Task layer that feeds it. For a
genuinely near-real-time pipeline you would keep Snowpipe/Streams landing
data continuously into a staging table, and either:
- point `models/staging/src_tpch.yml` at that staging table instead of
  the raw TPC-H sample data, and run `dbt run` on a tight schedule
  (dbt Cloud supports schedules down to a few minutes), or
- keep the native Stream+Task approach for ingestion and only use dbt
  for the Business Vault / Information Delivery layers downstream.

## How the pieces map

| Native Snowflake guide | This dbt project | Mechanism |
|---|---|---|
| `stg_customer_strm_outbound` / `stg_order_strm_outbound` (views with `SHA1_BINARY()`) | `models/staging/stg_customer.sql`, `stg_orders.sql` | `automate_dv.stage()` |
| `rv_hub_customer`, `rv_hub_order` | `models/raw_vault/hub_customer.sql`, `hub_order.sql` | `automate_dv.hub()`, incremental |
| `rv_sat_customer`, `rv_sat_order` | `models/raw_vault/sat_customer_details.sql`, `sat_order_details.sql` | `automate_dv.sat()`, incremental |
| `rv_lnk_customer_order` | `models/raw_vault/link_customer_order.sql` | `automate_dv.link()`, incremental |
| `ref_nation`, `ref_region` | `models/staging/ref_nation.sql`, `ref_region.sql` | plain table models |
| `bv_sat_customer` (view) | `models/business_vault/bv_sat_customer.sql` | plain view, `QUALIFY` for current row |
| `bv_sat_order` (Stream+Task, tier-bucket rule) | `models/business_vault/bv_sat_order.sql` | incremental model, same `CASE` logic |
| `dim1_customer`, `dim1_order` | `models/marts/dim_customer.sql`, `dim_order.sql` | views |
| `fct_customer_order` | `models/marts/fct_customer_order.sql` | view |
| Primary/foreign key `CONSTRAINT`s (unenforced by Snowflake) | `models/raw_vault/raw_vault.yml` | actual dbt tests (`unique`, `not_null`, `relationships`) — these genuinely run and fail the build |

Hash keys are computed identically in spirit: AutomateDV's `hashed_columns`
config generates the same kind of SHA1 hash the native guide built by
hand with `SHA1_BINARY(UPPER(TRIM(...)))`. Set `hash: "SHA1"` in
`dbt_project.yml` (already done) to match.

## Setup

1. Install dependencies:
   ```
   dbt deps
   ```
2. Configure a Snowflake profile named `tpch_data_vault` in
   `~/.dbt/profiles.yml` pointing at a role/warehouse that can read
   `SNOWFLAKE_SAMPLE_DATA.TPCH_SF10` (e.g. `ACCOUNTADMIN` or
   `QA_ANALYST` from the native guide's setup, if you ran that first;
   any role with read access to the sample data share works).
3. Run:
   ```
   dbt run
   ```
4. Test:
   ```
   dbt test
   ```
5. Re-run to see the incremental models behave — see the two feeding
   modes below.

## Two ways to feed the vault

The staging, vault and mart models are identical in both modes; only
`models/staging/base/base_customer.sql` / `base_orders.sql` switch on
`target.name`.

| | `dev` target (default) | `lz` target |
|---|---|---|
| Source | `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1` | `DEV_LZ.TPCH_CUSTOMER_SYS.stg_customer`, `DEV_LZ.TPCH_ORDERS_SYS.stg_orders` (Snowpipe-fed, from the native guide) |
| New data per run | Simulated with vars: `--vars '{order_batch: 2, customer_limit: 0}'` | Whatever Snowpipe has actually landed since the last run |
| LOAD_DATETIME / RECORD_SOURCE | `CURRENT_TIMESTAMP()` / constant | Real ingestion metadata: `ldts` / `rsrc` |
| Setup needed | None beyond the three output databases | DVArchitecture.sql + DVRealTime.sql Landing Zone steps |
| Schemas | `dev_*` | `dev_lz_*` (never mixes with `dev`) |

```
dbt build                      # dev: batch simulation
dbt build --target lz          # lz: read the landing zone
dbt source freshness --target lz
```

Findings from the landing zone (the guide's own DDL, not this project):
- `stg_orders.o_totalprice` is declared `NUMBER` (scale 0), so Snowpipe rounds
  prices to whole units on load (1,978 of the first 2,000 orders). dbt casts it
  back to `NUMBER(12,2)` but the cents are already gone.
- Hub hash keys built by AutomateDV are byte-identical to the guide's
  `SHA1_BINARY(UPPER(TRIM(key)))` (0 differences either way on 1.5M customers
  and 2,000 orders). Hashdiffs differ by design — the guide concatenates with
  `ARRAY_TO_STRING` in declared column order, AutomateDV uses `CONCAT_WS('^')`
  over alphabetically sorted columns — so don't mix the two vaults' satellites.
- The guide's pipes use an unqualified target (`COPY INTO stg_orders`), so
  `ALTER PIPE ... REFRESH` fails with "Table 'STG_ORDERS' does not exist" unless
  the session is in that schema first: `USE SCHEMA DEV_LZ.TPCH_ORDERS_SYS;`.

Loading a new batch for the `lz` target (run in Snowsight, then `dbt build --target lz`):

```sql
COPY INTO @DEV_LZ.TPCH_ORDERS_SYS.orders_data
FROM (SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF10.ORDERS
      WHERE o_orderkey > <current max o_orderkey> ORDER BY o_orderkey LIMIT 1000)
INCLUDE_QUERY_ID = TRUE;
USE SCHEMA DEV_LZ.TPCH_ORDERS_SYS;
ALTER PIPE stg_orders_pp REFRESH;
```

## Where dbt genuinely improves on the hand-written SQL

- **No repeated hashing logic.** `SHA1_BINARY(UPPER(TRIM(...)))` for every
  hash key/hashdiff is written once, in the package, not by hand in every
  model.
- **Real tests, not just unenforced `CONSTRAINT`s.** Snowflake doesn't
  enforce PK/FK; `dbt test` actually fails the build if a hub has
  duplicate keys or a link references a hub that doesn't exist.
- **Auto-generated docs and lineage.** `dbt docs generate && dbt docs serve`
  gives you the same kind of ERD Snowflake's guide had to hand-draw as a
  PNG.
- **One place to change the hashing algorithm or delimiter** — the
  `vars: automate_dv:` block in `dbt_project.yml`, instead of hunting
  down every `SHA1_BINARY(...)` call in every model.

## Where the native Snowflake guide still wins

- **True streaming ingestion.** Snowpipe + Streams process rows the
  moment they land; dbt only runs when invoked.
- **Multi-table insert in one transaction.** The native guide's
  `INSERT ALL ... WHEN ... THEN INTO` populates hub + satellite + link
  in a single atomic statement. AutomateDV builds hub, link, and
  satellite as *separate* incremental models — functionally equivalent
  results, but as three statements, not one.
- **Zero extra tooling.** No `dbt deps`, no package version pinning, no
  separate orchestration needed to trigger runs.
