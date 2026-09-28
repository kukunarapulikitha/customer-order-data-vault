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
4. `dbt debug` must pass all checks.

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

## Phase 6 — Extra tests
Add to a `models/marts/marts.yml` and `tests/`:
- `unique` + `not_null` on dim_customer.CUSTOMER_ID, dim_order.ORDER_ID.
- `accepted_values` on dim_order.ORDER_PRIORITY_BUCKET: Tier-1, Tier-2, Tier-3.
- Singular test `tests/assert_tier1_rule.sql`: returns rows where bucket = 'Tier-1'
  but priority not in ('1-URGENT','2-HIGH') or totalprice < 200000.
- Singular test `tests/assert_sat_no_duplicate_hashdiff.sql`: same PK + hashdiff
  appearing more than once in sat_order_details.
Run `dbt test`, all green.

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
