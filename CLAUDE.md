# CLAUDE.md — TPC-H Data Vault on dbt Core (AutomateDV)

Portfolio project: rebuild Snowflake's "Real-Time Data Vault" guide
(TPC-H customers/orders) as a dbt Core project using AutomateDV.
See README.md for the model-by-model mapping to the native Snowflake SQL.

## Ground rules
- Work phase by phase. Stop and report at the end of each phase before continuing.
- Never write credentials into any file. Snowflake creds come from env vars only
  (SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD). If they aren't set,
  ask the user to export them — don't prompt for the password in chat.
- Use a project-local virtualenv (.venv). Don't install packages globally.
- If a command fails, show the error, diagnose, and propose a fix before retrying.
- Don't change the Data Vault design (hash keys, hashdiff columns, tier rule)
  without asking. Fixing syntax/compatibility issues is fine.

## Phase 0 — Location
- Target folder: the user's "Portfolio Projects" directory. Find it
  (e.g. ~/Portfolio Projects, ~/Documents/Portfolio Projects); if ambiguous, ask.
- Project lives at `<Portfolio Projects>/tpch-data-vault-dbt/`.
- `git init`, first commit with the scaffold as-is.

## Phase 1 — Environment
1. `python3 --version` — need 3.9–3.12 (dbt-snowflake support). If 3.13+, use pyenv/uv for 3.12.
2. `python3 -m venv .venv && source .venv/bin/activate`
3. `pip install -r requirements.txt`
4. `dbt --version` — confirm dbt-core and snowflake adapter both listed.

## Phase 2 — Snowflake connection
1. Copy `profiles.yml.example` → `./profiles.yml` (gitignored). Run dbt with
   `--profiles-dir .` or set `DBT_PROFILES_DIR=.`.
2. Ask the user which role/warehouse to use. Options:
   - Fresh trial: role SYSADMIN, warehouse COMPUTE_WH.
   - If DVArchitecture.sql was run: ENGINEERING_WH works.
3. Target database `DBT_DV` must exist. If not, give the user this to run in Snowsight
   (don't run DDL yourself unless asked):
   `CREATE DATABASE IF NOT EXISTS DBT_DV;`
4. `dbt debug` must pass all checks (on both `dev` and `lz` targets — see Phase 5b).

## Phase 3 — Dependencies & compile
1. `dbt deps`
2. Check installed AutomateDV version against the dbt-core version
   (AutomateDV 0.11.x supports dbt >= 1.9). Adjust packages.yml if needed.
3. Verify AutomateDV var names in dbt_project.yml against the installed version's docs
   (`hash`, `concat_string`, `null_placeholder_string`). Remove any var the
   package doesn't recognise (e.g. `null_placeholder_num` is likely unused).
   Confirm `SHA1` is a valid `hash` value; if not, fall back to `SHA` and note it in README.
4. `dbt compile` — fix any Jinja/macro-signature errors. Show compiled SQL for
   `hub_customer` and `sat_customer_details` so the user can compare against
   DVRealTime.sql.

## Phase 4 — First build (batch 1)
1. `dbt build` (defaults: 10 customers, orders 1–1000).
2. Expected: all models build, all tests pass.
3. Row-count check query (run via `dbt show --inline` or give to user):
   hub_customer=10, hub_order=1000, link=1000, sat_customer=10, sat_order=1000,
   bv_sat_order=1000. `fct_customer_order` likely ~0 rows (inner joins; the
   10 customers probably don't own any of the first 1000 orders). Also
   `relationships` test on link → hub_customer will likely FAIL here — that's
   the guide's intentional late-arriving-data scenario, not a bug. Report it.

## Phase 5 — Incremental tests (the point of the project)
Run each, then re-check row counts:
1. `dbt run --vars '{order_batch: 2}'` → hub_order/sat_order/link = 2000,
   hub_customer unchanged. bv_sat_order = 2000.
2. `dbt run --vars '{order_batch: 2}'` again → counts unchanged (idempotency:
   hubs/links dedupe on PK, sats dedupe on hashdiff). If sats duplicate,
   investigate `apply_source_filter` config on sat models.
3. `dbt run --vars '{order_batch: 2, customer_limit: 0}'` → full customer load.
   Now fct_customer_order should be ~2000 and the relationships test should pass
   on `dbt test`.
4. Note: `order_batch: 2` only stages orders 1001–2000; orders 1–1000 are
   already in the vault from step 1. That's the incremental behavior being tested.

## Phase 5b — Landing Zone target (`--target lz`, no vars)
Alternative feed: read the native guide's Snowpipe-loaded tables instead of
simulating batches with vars. The vars path stays the default (`dev` target).
Prereq (user confirmed): DVArchitecture.sql + DVRealTime.sql Landing Zone steps are set up.
1. `profiles.yml` gets a second output `lz` (same creds, schema `dev_lz` so the
   two modes' incremental tables never mix).
2. `models/staging/src_lz.yml`: sources for `DEV_LZ.TPCH_CUSTOMER_SYS.stg_customer`
   and `DEV_LZ.TPCH_ORDERS_SYS.stg_orders`, enabled only when `target.name == 'lz'`,
   with `loaded_at_field: ldts` for `dbt source freshness`.
3. `base_customer` / `base_orders` branch on `target.name == 'lz'`: parse
   `raw_json` for customers, explicit `o_*` columns for orders, and use the LZ
   `ldts` / `rsrc` as LOAD_DATETIME / RECORD_SOURCE. Nothing downstream changes.
4. Give the user (don't run): grants for dbt's role on DEV_LZ; suggest suspending
   the guide's Tasks (dbt doesn't need the streams); batch unloads with
   `ORDER BY o_orderkey LIMIT 1000 OFFSET n` + `ALTER PIPE ... REFRESH`.
5. Verify: build on current LZ contents → load next order batch → counts +1000 →
   re-run with no new files → unchanged → load all customers → relationships test passes.

## Phase 6 — Extra tests
Add to a `models/marts/marts.yml` and `tests/`:
- `unique` + `not_null` on dim_customer.CUSTOMER_ID, dim_order.ORDER_ID.
- `accepted_values` on dim_order.ORDER_PRIORITY_BUCKET: Tier-1, Tier-2, Tier-3.
- Singular test `tests/assert_tier1_rule.sql`: returns rows where bucket = 'Tier-1'
  but priority not in ('1-URGENT','2-HIGH') or totalprice < 200000.
- Singular test `tests/assert_sat_no_duplicate_hashdiff.sql`: same PK + hashdiff
  appearing more than once in sat_order_details.
Run `dbt test`, all green.

## Phase 6b — Hand-written Data Vault (no AutomateDV) + PIT
Same vault built with plain dbt SQL, side by side, proven equal by tests.
1. `macros/dv_hash.sql` — replicate AutomateDV's compiled hashing exactly (read
   `target/compiled/.../stg_customer.sql` first: SHA1, `^`, `-1` nulls, UPPER/TRIM,
   hashdiff column order).
2. `models/staging/native/stg_*_native.sql` over the shared base models.
3. `models/raw_vault_native/` (schema `raw_vault_native`), incremental append:
   hubs/link insert unseen keys only; sats insert only when hashdiff differs from
   the latest stored row per key (and from the previous row within the batch).
   Same PK/FK tests as `raw_vault.yml`.
4. `tests/reconcile/` — one singular test per vault table:
   `(automate_dv EXCEPT native) UNION ALL (native EXCEPT automate_dv)` must return 0 rows.
   Exclude LOAD_DATETIME on `dev` (CURRENT_TIMESTAMP differs per view); include it on `lz`.
5. `models/business_vault/as_of_dates.sql` + `pit_customer.sql` via `automate_dv.pit()`.
6. README: AutomateDV vs hand-written comparison.

## Phase 7 — Analytics query & docs
1. Add `analyses/orders_by_region_tier.sql` — the native guide's final
   nation/region/tier breakdown query, rewritten with `ref()`s. `dbt compile` it
   and run with `dbt show`.
2. `dbt docs generate` then `dbt docs serve` — confirm lineage graph shows
   staging → raw_vault → business_vault → marts.

## Phase 8 — Portfolio polish
- Update README: actual row counts from Phase 5, screenshots placeholder for lineage,
  "what I learned" section left for the user to write (don't write it for them).
- Optional GitHub Actions workflow running `dbt build` on PRs is out of scope
  unless the user asks (needs secrets).
- Commit per phase with clear messages.

## Cost hygiene
- Everything is views or small incremental tables on TPCH_SF1; XS warehouse is plenty.
- Remind the user to set AUTO_SUSPEND = 60 on the warehouse if it isn't already.
