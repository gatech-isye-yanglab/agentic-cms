# Prompt 01 — Schema-exact synthetic CMS database

## Goal

Generate `synthetic_data/` — a self-contained module that, given the
institutional schema export at `seed/data/columns_formats.csv`,
produces a 21-table, ~657k-row synthetic CMS Medicaid database in
SQLite (and optionally MySQL) in ~2.5 minutes.

The synthetic DB must be **identifier-exact** — same column names,
same case sensitivity, same types as the institutional schema — so
SQL written against it either passes against real data or fails for
a non-schema reason.

## Files to generate (under `synthetic_data/`)

| File | Purpose |
|---|---|
| `gen_ddl.py` | Parse `seed/data/columns_formats.csv` → emit `schema_mysql.sql` and `schema_sqlite.sql`. |
| `gen_data.py` | Tier 1 generator: Python random draws bootstrapped from DE-SynPUF Sample 1, six cohort buckets tuned to the diabetes pipeline's filter logic. |
| `load_rif.py` | Tier 2a loader: transform CMS Synthetic RIF 2023 (Medicare claims) into the TAF tables, with SSA→USPS state crosswalk and a Python oncology HCPCS overlay. |
| `ssa_state_crosswalk.py` | SSA numeric state code → USPS postal map. Used by `load_rif.py`. |
| `build_cms_source.sh` | Orchestrator: runs `gen_ddl.py` → `gen_data.py` → `load_rif.py` → optional MySQL load → pytest. |
| `load_mysql.sql` | `LOAD DATA LOCAL INFILE` for all 21 tables. |
| `seed_mysql.py` | Pure-Python fallback loader (no `--local-infile=1` needed). |
| `download_synthetic_data.sh` | Prose instructions naming CMS landing pages for the public input datasets. |
| `columns_formats.csv` | Copy of `seed/data/columns_formats.csv`. |
| `README.md` | Self-contained documentation of the build. |
| `KNOWN_GAPS.md` | Honest enumeration of what's missing (e.g. Synthea doesn't model Part B oncology J/C codes). |

## Critical invariants

### Schema fidelity

`gen_ddl.py` reads `columns_formats.csv` (columns: `table_name,
column_order, column_name, full_type, is_nullable`) and emits CREATE
TABLE statements with **column names byte-identical to the CSV**.
This is non-negotiable. If you "fix" inconsistent casing
(`patient_id` vs `PATIENT_ID`, `state_key` vs `STATE_KEY`), agent-
generated SQL will work against synthetic and fail against real
data. The institutional schema is intentionally inconsistent across
eras.

A MySQL → SQLite type translation function maps:
- `varchar(N)` and `date`, `timestamp` → `TEXT`
- `decimal(*)` → `REAL`
- `int`, `bigint`, `tinyint` → `INTEGER`
- Anything unrecognised → raise `ValueError` (do not silent-cast)

### Era distribution and bucket allocation

`gen_data.py` uses a fixed seed (`SEED = 42`) for reproducibility.
Every patient is assigned:

- An **era** (1, 2, or 3) drawn 40/25/35 from `rng`, where
  - era 1 = MAX 2005-2012, columns `YR_NUM` / `EL_DOB` / `DIAG_CD_1..9`
  - era 2 = MAX 2013-2015, same column shape as era 1 plus `inpatient1315` table family
  - era 3 = TAF 2016+, columns `RFRNC_YR` / `BIRTH_DT` / `DGNS_CD_1..12`
- A **bucket** drawn from position-in-list (deterministic): 40% `positive`, 20% `single`, 15% `long_gap`, 10% `wrong_state`, 10% `no_diabetes`, 5% `ambiguous`. Era and bucket must be independent.
- A **state** drawn from one of:
  - 7 SE states (`AL, FL, GA, MS, NC, SC, TN`) for non-`wrong_state` buckets
  - The full set of non-SE states for `wrong_state`

Each bucket gets specific date and diagnosis-code patterns. **All
dates must remain inside the era's year window** — the test
`test_year_ranges_match_era` will fail if a `long_gap` ERA1 patient's
second claim lands in 2014 (ERA2 territory). Clamp the second date
with `min(d1 + gap_days, date(y1, 12, 31))`:

- `positive`: 2 claims, 30–700 days apart, qualifying ICD codes; both inside era window
- `single`: 1 claim only
- `long_gap`: 2 claims, 731–900 days apart, **both inside era window**
- `wrong_state`: 2 claims in a non-SE state
- `no_diabetes`: 1 claim with non-diabetes ICD only
- `ambiguous`: 2 claims with sex toggling between them

### Track distribution and target row counts

Each patient gets at least one of: inpatient claim, outpatient claim,
RX claim. Tracks are drawn independently per patient:
`show_inp = rng.random() < 0.55`, `show_out = rng.random() < 0.55 if
show_inp else True` (always outpatient if no inpatient), `show_rx =
rng.random() < 0.30`. This gives outpatient slightly higher row
volume than inpatient, matching canonical:

| Table | Canonical count (SEED=42, n=all ≈116k) |
|---|---|
| `inpatient` | 43,209 |
| `inpatient1315` | 27,134 |
| `other_therapy` | 59,205 |
| `other_therapy1315` | 37,663 |
| `personal_summary` | 46,265 |
| `personal_summary1315` | 29,276 |
| `rx` | 23,558 |
| `rx1315` | 15,145 |

Outpatient (`other_therapy*`) is ~37% larger than inpatient because
the always-outpatient-if-no-inpatient fallback bumps it. A regenerated
build should produce counts within ±5% of these for the SQLite path.

### Tier 2a oncology overlay (load_rif.py)

The CMS Synthetic RIF 2023 has zero oncology J/C codes — only
preventive G-codes (38 distinct values across 1.7M rows). For the
~25 Synthea-flagged lung-cancer beneficiaries in the RIF cohort,
load_rif.py must:

1. Detect lung-cancer beneficiaries by scanning ICD codes against a
   small set: `162, 1622-1629, 2312` (ICD-9) and `C34, C340-C3492,
   D022-D0222` (ICD-10).
2. For each one, with treatment-type distribution `45% chemo / 35%
   immuno / 10% mixed / 10% untreated`, append 6–24 synthetic
   `taf_other_services_line` rows with HCPCS J/C codes drawn from
   chemo / immuno pools.
3. Tag overlay rows with `CLM_ID` prefix `ONCO` so they're
   distinguishable from real RIF rows downstream.

### Validation

After `gen_ddl.py` + `gen_data.py` + `load_rif.py` run, the synthetic
DB must satisfy (these are the tests in prompt 08):

- 21 tables, 2,533 columns total.
- BENE_ID consistency: every claim row's BENE_ID must appear in the
  matching demographics table.
- Partition columns populated: `state_key` / `STATE_KEY` and year
  columns are non-NULL on every claim row.
- Year ranges per era: MAX-1 in 2005–2012, MAX-2 in 2013–2015, TAF
  in 2016–2025.
- Partition filter reduces row count strictly.
- Step-1 extractions (filtered by ICD-9 25x in MAX-1 / ICD-9+ICD-10
  in MAX-2 / ICD-10 E1x in TAF) produce >0 rows in each era.
- Step-3 SE-state filter strictly reduces row count.
- Step-4 two-year-rule cohort is non-empty.

## build_cms_source.sh — orchestrator

```bash
#!/usr/bin/env bash
# Order: gen_ddl → gen_data → load_rif → optional MySQL load → pytest.
# Honor SKIP_MYSQL=1 to bypass the MySQL load step (default for laptops).
# Preflight: check that synthetic_data/de_synpuf_2008_2010/ and
# synthetic_data/synthetic_rif_2023/ exist; if not, exit 2 with a
# clear message pointing at download_synthetic_data.sh.
```

The preflight check is load-bearing for stranger reproducibility — a
cold clone without the public datasets must hit a friendly error,
not a `FileNotFoundError` traceback.

## download_synthetic_data.sh

Prose-only. CMS distributes both inputs from landing pages that
hand-roll download links per visit; direct curl isn't possible.
Document the URLs and target paths:

- DE-SynPUF 2008-2010 Sample 1: https://www.cms.gov/data-research/statistics-trends-and-reports/medicare-claims-synthetic-public-use-files/cms-2008-2010-data-entrepreneurs-synthetic-public-use-file-de-synpuf
- CMS Synthetic RIF 2023: https://data.cms.gov/collection/synthetic-medicare-enrollment-fee-for-service-claims-and-prescription-drug-events

Target layout:

```
synthetic_data/de_synpuf_2008_2010/DE1_0_2008_Beneficiary_Summary_File_Sample_1.csv
synthetic_data/synthetic_rif_2023/{beneficiary_YYYY,inpatient,outpatient,pde}.csv
```

## See also

- The full-repo equivalents at `synthetic_data/{gen_ddl.py, gen_data.py, load_rif.py, ssa_state_crosswalk.py, build_cms_source.sh, README.md, KNOWN_GAPS.md}`.
- Prompt 08 for the validation harness that verifies what this prompt produces.
- `seed/evidence/row_counts_v1.json` for the canonical-run row counts.
