# Prompt 08 — Validation harness, toy_db fixture, agent demo tests

## Goal

Generate the test layer that validates everything prompts 01-07
produced. Three components:

1. **Synthetic-DB compliance harness** (`synthetic_data/tests/`) —
   25 unittest test cases / 83 subtests that pass against the
   SQLite synthetic build. No external services.
2. **toy_db MySQL fixture** (`toy_db/`) — a small ~1,400-row MySQL
   fixture used to drive the agent's smoke tests in seconds.
3. **Agent demo tests** (`tests/`) — two end-to-end tests of the
   ReAct loop driving GPT-4o against the populated `cms_source` DB,
   plus their saved traces.

## Files to generate

### synthetic_data/tests/test_synthetic_db.py — the headline test

A single Python file exporting 5 unittest classes covering 4
categories of checks. Total **25 named tests** and **83 subtests**
when run with `pytest-subtests`. The subtest count is exact, not
approximate, and is asserted by the verify script. The 83 comes from:

| Test | Subtests |
|---|---|
| `test_column_names_and_order_match_csv` (iter over 21 tables) | 21 |
| `test_column_types_match_affinity` (iter over 21 tables) | 21 |
| `test_header_line_clm_id_linkage` (3 header/line pairs) | 3 |
| `test_state_codes_lookup_covers_claim_states` (3 source tables) | 3 |
| `test_state_key_populated` (6 MAX claim tables) | 6 |
| `test_STATE_KEY_populated_in_taf` (7 TAF tables) | 7 |
| `test_year_columns_populated` (9 (table, col) pairs) | 9 |
| `test_year_ranges_match_era` (4 era bounds) | 4 |
| `test_table_counts_nonzero_for_populated_tables` (9 tables) | 9 |
| **Total subtests** | **83** |

The remaining 16 of the 25 named tests use no `subTest` (e.g.
`test_all_21_tables_present`, `test_total_column_count`) and count
once each.

Open the SQLite DB with `sqlite3.connect(f"file:{path}?mode=ro&immutable=1", uri=True)`
to skip lock acquisition (some FUSE/virtiofs mounts don't support
SQLite's POSIX locking).

**Class 1: SchemaIntegrity (4 tests)**

- `test_all_21_tables_present` — `EXPECTED_TABLES` list of 21 names
  matches `sqlite_master`.
- `test_column_names_and_order_match_csv` — for each table, `PRAGMA
  table_info(t)` column names match `seed/data/columns_formats.csv`
  column-order. Uses `subTest(table=t)`.
- `test_column_types_match_affinity` — types match the
  MySQL→SQLite mapping rules. Subtest per table.
- `test_total_column_count` — total across 21 tables is exactly
  `2533`.

**Class 2: ReferentialIntegrity (5 tests)**

- `test_bene_ids_consistent_between_claim_and_demographics_era1` —
  every `inpatient.BENE_ID` appears in `personal_summary`.
- `_era2` — same for `inpatient1315` ↔ `personal_summary1315`.
- `_era3` — same for `taf_inpatient_header` ↔ `taf_demog_elig_base`.
- `test_header_line_clm_id_linkage` — every line-table CLM_ID
  appears in the matching header table (3 pairs: inpatient,
  other_services, rx). Subtest per pair.
- `test_state_codes_lookup_covers_claim_states` — every observed
  STATE_CD on a claim row appears in `state_codes`. Subtest per
  source table.

**Class 3: PartitionFilters (5 tests)**

- `test_state_key_populated` — for each MAX-era claim table, no
  NULL `state_key`. Subtest per table.
- `test_STATE_KEY_populated_in_taf` — same for TAF tables, all 7.
- `test_year_columns_populated` — `YR_NUM` (MAX) / `RFRNC_YR` (TAF)
  populated. Subtest per (table, col) pair.
- `test_partition_filter_reduces_rows` — `state_key=1 AND YR_NUM=2010`
  filter on `inpatient` returns ≤ total row count, and total > 0.
- `test_year_ranges_match_era` — MAX-1 in 2005-2012, MAX-2 in
  2013-2015, TAF in 2016-2025 (TAF widened to accommodate Tier 2a
  RIF data through 2025).

**Class 4: DiabetesPipelineSmoke (6 tests)**

- `test_step1_extract_era1_inpatient_diabetes` — ICD-9 `'250%'`
  filter on `inpatient` 2005-2012 returns >0 rows.
- `_era2` — ICD-9 OR ICD-10 (`'250%' OR 'E1%'`) on `inpatient1315`.
- `_era3` — ICD-10 `'E1%'` on `taf_inpatient_header` 2016-2025.
- `test_step3_se_state_filter_reduces_count` — SE-state filter on
  `taf_inpatient_header` strictly reduces row count (because
  wrong_state seeded patients exist).
- `test_step4_two_year_rule_yields_cohort` — UNION of three eras'
  diabetes claims, JOIN on BENE_ID with date-difference ≤ 730 →
  non-empty patient set.
- `test_bucket_labels_consistent` — at least some `inpatient` rows
  are in non-SE states (validates `wrong_state` bucket).

**Class 5: MetaTables (5 tests)**

- `test_data_years_has_19_rows` — covers 2005-2023 inclusive.
- `test_data_years_span_2005_2023` — values match
  `range(2005, 2024)`.
- `test_state_codes_has_60_rows`.
- `test_table_counts_covers_21_tables` — `table_counts` rows match
  `EXPECTED_TABLES`.
- `test_table_counts_nonzero_for_populated_tables` — 9 specifically
  named claim/demographics tables report >0 rows.

### toy_db/ — small MySQL fixture

| File | Purpose |
|---|---|
| `schema.sql` | Minimal `cms_source` schema: 6 source tables + 2 meta (`state_codes`, `data_years`). Identifier-exact for the columns the diabetes pipeline reads, but a small subset of `synthetic_data/columns_formats.csv` (which has 2,533 columns; toy needs ~70). |
| `seed_mysql.py` | Applies `schema.sql`, then INSERTs 1,000 patients × 6 buckets × 3 eras = ~1,400 claim rows. Uses `SEED = 42` for reproducibility. Same 6-bucket pattern as `synthetic_data/gen_data.py` but scaled down. |
| `run_sql.py` | Loads `pipelines/diabetes/{reference,step1_extraction,step2_combine,step3_filter}/*.sql` via `agents.tools.sql_split.split_by_delimiter`. Imports the splitter from `agents/`, NOT a duplicate copy. |
| `README.md` | Clarifies the toy_db / synthetic_data role split — same `cms_source` schema name, different scales, different purposes. |

`schema.sql` content: 6 CREATE TABLEs with exactly the columns
specified in the table at the top of `extraction_cursor.md` skill.
Plus `state_codes(state_code VARCHAR(2), state_key INT, PRIMARY KEY
(state_code))` and `data_years(year_num INT PRIMARY KEY)`.

`seed_mysql.py` patient-id ranges:
- P0001-P0250 → ERA1 inpatient (2005-2012)
- P0251-P0450 → ERA2 inpatient (2013-2015)
- P0451-P0600 → ERA1 outpatient (2005-2012)
- P0601-P0700 → ERA2 outpatient (2013-2015)
- P0701-P0900 → ERA3 TAF inpatient (2016-2018)
- P0901-P1000 → ERA3 TAF outpatient (2016-2018)

Each range is bucket-distributed 40/20/15/10/10/5 with the same
date and code patterns as `synthetic_data/gen_data.py`.

### tests/ — agent demo tests

| File | Purpose |
|---|---|
| `test_minimal_extraction.py` | Single-step ReAct loop. Imports `agents.llm.LLM_STRONG`, `agents.tools.mysql_tools.SQL_TOOLS`, `knowledge.constraints.check_partition_filter`, `knowledge.task_builder.build_extraction_task`, `knowledge.diseases.diabetes`. Builds a task for ERA1 inpatient extraction, runs up to 3 critic-retry rounds, verifies the output table is non-empty AND the partition-filter Critic passes. Saves a full trace to `tests/trace_minimal_extraction.txt`. |
| `test_step1_and_2.py` | Full Step 1 + Step 2: three ERAs extracted sequentially, then unioned into `all_combine`. Each step has up to 3 critic-retry rounds. Saves `tests/trace_step1_and_2.txt`. |
| `trace_minimal_extraction.txt` | Carry over from `seed/evidence/traces_v1.txt` if present. Or a placeholder note: "Trace will be generated on first agent run." |
| `trace_step1_and_2.txt` | Same. |
| `README.md` | Documents what each test exercises, what saved traces show, and the repro path (Python deps + MySQL + Azure). |

The tests' shape (Tracer class, `_invoke_tool`, `_strip_fences`,
`_row_count`, `_build_critic_feedback`, `_preflight_check`) is
described in detail in the `agents/README.md` section "Running the
demo." A regenerating agent should reproduce the structure but not
worry about byte-equality of the prose in the Tracer's section
headers.

The tests' preflight checks emit hint paths:

```
("icd_9_cm",    "SELECT COUNT(*) FROM icd_9_cm",
 "run: python3 toy_db/run_sql.py"),
("state_codes", "SELECT COUNT(*) FROM state_codes",
 "run: python3 toy_db/seed_mysql.py"),
```

Verify that a stranger reading the failure message can recover.

## verify.sh — what the seed's outer verification does

(This is generated as `seed/verify.sh`, not in the regenerated
artifact.) The verification script:

1. Cd into the regenerated artifact root.
2. Run `bash synthetic_data/build_cms_source.sh` (with `SKIP_MYSQL=1`).
   Compare the build's reported row counts to
   `evidence/row_counts_v1.json`. Pass if within ±5%.
3. Run `pytest synthetic_data/tests/`. Pass if 25/25 named tests
   pass (subtests count is informational).
4. (Optional, if MySQL is available) Run
   `python3 toy_db/seed_mysql.py && python3 toy_db/run_sql.py` then
   `bash pipelines/diabetes/run_pipeline.sh`. Pass if the pipeline
   completes and `single_row_patient_temp` is non-empty.
5. Compute SHA-256 of `synthetic_data/synthetic_db.sqlite` and
   compare to `evidence/synthetic_db_seed42.sha256`. Note: equality
   means **fully deterministic regeneration** — a strong signal but
   not strictly required for behavioral pass.
6. Output a fidelity score: `tests_passed / 25` × 100%.

## See also

- Full-repo equivalents at `synthetic_data/tests/test_synthetic_db.py`, `toy_db/{schema.sql, seed_mysql.py, run_sql.py, README.md}`, `tests/{test_minimal_extraction.py, test_step1_and_2.py, README.md, trace_*.txt}`.
- `seed/evidence/` for the canonical-run outputs to compare against.
- `seed/verify.sh` for the orchestrating verification script.
