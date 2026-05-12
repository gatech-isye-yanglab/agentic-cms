# Synthetic CMS Database — Design Notes

The agent runs only against synthetic data. This document explains
how the synthetic database in [`synthetic_data/`](../synthetic_data/)
is built, what it does and doesn't cover, and why it's faithful enough
to the institutional schema that SQL passing here either passes
against real data or fails for a non-schema reason.

## Bottom line

`bash synthetic_data/build_cms_source.sh` (or
`SKIP_MYSQL=1 bash synthetic_data/build_cms_source.sh` on a laptop
without MySQL) produces a 21-table, 2,533-column synthetic CMS
database in ~2.5 minutes. `pytest synthetic_data/tests/` validates it
in <1 second across 25 tests / 83 subtests.

## Era-aware schema crosswalk — the core fidelity claim

The institutional CMS Medicaid database spans three schema eras with
**different column names for the same concept**:

| Concept | MAX 2005–2012 | MAX 2013–2015 | TAF 2016+ |
|---|---|---|---|
| Patient ID | `patient_id` (lowercase) | `patient_id` | `PATIENT_ID` (uppercase) |
| Year | `YR_NUM` | `YR_NUM` | `RFRNC_YR` |
| State partition | `state_key` | `state_key` | `STATE_KEY` |
| Date of birth | `EL_DOB` | `EL_DOB` | `BIRTH_DT` |
| Diagnosis cols | `DIAG_CD_1..9` | `DIAG_CD_1..9` | `DGNS_CD_1..12` |
| Inpatient table | `inpatient` | `inpatient1315` | `taf_inpatient_header` |
| Outpatient table | `other_therapy` | `other_therapy1315` | `taf_other_services_header` |

Combined with the ICD-9 → ICD-10 transition (Oct 1, 2015), partition-
filter requirements (every query needs `state_key` + year filter or it
gets killed), and per-disease clinical criteria (e.g. *"two qualifying
claims on different dates within 730 days"* for incident diabetes),
this schema is unforgiving. A naive LLM that emits a generic SQL
template fails immediately. A specialised agent with a skill file
encoding the cursor pattern, plus a Critic checking partition filters
and column names, has a fighting chance.

## Architecture — a hybrid, three-module build

```
   ┌─────────────────────────────────────────────────────────┐
   │  columns_formats.csv  (institutional schema export —    │
   │                        column metadata, no rows)        │
   └────────────────────────────┬────────────────────────────┘
                                │
                                ▼
   ┌─────────────────────────────────────────────────────────┐
   │  gen_ddl.py                                             │
   │   → schema_mysql.sql   (21 CREATE TABLEs, MySQL types) │
   │   → schema_sqlite.sql  (same, with SQLite affinities)  │
   │   Identifiers preserved byte-for-byte.                 │
   └────────────────────────────┬────────────────────────────┘
                                │
              ┌─────────────────┴────────────────────┐
              │                                      │
              ▼                                      ▼
   ┌────────────────────────────┐       ┌────────────────────────────┐
   │  Tier 1 — gen_data.py      │       │  Tier 2a — load_rif.py     │
   │  (MAX era 2005-2015 +      │       │  (TAF era 2016+ from CMS    │
   │   meta-tables)             │       │   Synthetic RIF 2023, plus  │
   │                            │       │   Python oncology HCPCS     │
   │  Python random draws       │       │   overlay for lung-cancer   │
   │  bootstrapped from         │       │   beneficiaries Synthea     │
   │  DE-SynPUF Sample 1        │       │   doesn't otherwise model)  │
   │  ~116k beneficiaries,      │       │  ~9k Synthea-derived        │
   │  6 cohort buckets          │       │  beneficiaries, realistic   │
   └────────────┬───────────────┘       │  timelines + demographics   │
                │                       └────────────┬────────────────┘
                │                                    │
                └─────────────┬──────────────────────┘
                              ▼
                    ┌──────────────────────┐
                    │  cms_source DB       │
                    │  21 tables × 2,533   │
                    │  columns             │
                    └──────────────────────┘
                              │
                              ▼
                    ┌──────────────────────┐
                    │  pytest 25 tests     │
                    │   • schema integrity │
                    │   • referential      │
                    │     integrity        │
                    │   • partition cols   │
                    │     populated        │
                    │   • Step-1/3/4       │
                    │     row-count gates  │
                    └──────────────────────┘
```

### Tier 1 — `gen_data.py` (MAX era + meta-tables)

Six cohort buckets tuned to exercise the diabetes pipeline's filtering
logic:

| Bucket | % | What the agent should find |
|---|---|---|
| `positive` | 40 | 2+ qualifying diabetes claims < 730 days apart in an SE state → keep |
| `single` | 20 | 1 qualifying claim → exclude (fails 24-month rule) |
| `long_gap` | 15 | 2 claims but > 730 days apart → exclude |
| `wrong_state` | 10 | Claims outside AL / FL / GA / MS / NC / SC / TN → excluded by Step 3 |
| `no_diabetes` | 10 | Non-diabetes ICD codes only → no cohort hits |
| `ambiguous` | 5 | Contradictory demographics across claims → flagged by Step 8 |

Era assignment (MAX 2005–12 vs MAX 2013–15 vs TAF 2016+) is
independent of bucket, so each test condition has examples in all
three schema eras.

### Tier 2a — `load_rif.py` (TAF era + oncology overlay)

Transforms CMS Synthetic RIF 2023 (Synthea-generated Medicare
beneficiaries) into the TAF tables, with SSA → USPS state crosswalk
and a Python overlay for oncology HCPCS J/C codes that Synthea's RIF
2023 doesn't emit. The overlay is explicitly tagged (`CLM_ID` prefix
`ONCO`) so anyone downstream can distinguish overlay rows from
real-RIF rows.

The oncology overlay closes a gap that would otherwise make the
lung-cancer pipeline produce zero rows on the synthetic build:
Synthea's RIF returns 38 distinct HCPCS codes, all preventive /
screening / counseling G-codes — zero J-codes, zero C-codes, the
single J9600 (Levoleucovorin). For each Synthea-flagged lung-cancer
beneficiary, `load_rif.py` appends 6–24 synthetic
`taf_other_services_line` rows with J/C codes drawn from chemo and
immuno HCPCS pools. See
[`synthetic_data/KNOWN_GAPS.md`](../synthetic_data/KNOWN_GAPS.md) for
the full discovery and rationale.

## Schema fidelity — strong on identifiers, partial by era

**Identifiers exactly preserved.** `DIAG_CD_1..9` vs `DGNS_CD_1..12`,
`YR_NUM` vs `RFRNC_YR`, `EL_DOB` vs `BIRTH_DT`, mixed-case `state_key`
vs `STATE_KEY`, lowercase `patient_id` vs uppercase `PATIENT_ID`. The
agent's SQL therefore breaks identically on real vs synthetic — no
false-pass risk from naming drift.

**Where fidelity weakens.** Synthea's RIF carries about 25 lung-cancer
beneficiaries and (originally) zero Part B oncology J/C codes. The
Python overlay is an explicit workaround. Same gap applies to
diabetes treatment claims — Synthea doesn't emit insulin J-codes
(J1815, J1817–J1819), test strips (A4253), or therapeutic shoes
(A5500–A5512).

## Two cohort regimes — don't conflate

| Folder | Purpose | Scale |
|---|---|---|
| [`synthetic_data/`](../synthetic_data/) | Schema-exact public Medicaid sandbox; the headline contribution. Used by anyone running cohort pipelines. | ~116k beneficiaries, ~657k rows |
| [`toy_db/`](../toy_db/) | Compact MySQL fixture for the agent's smoke tests, tuned to make the GPT-4o ReAct loop terminate in <60 s. | 1,000 patients, ~1,400 claim rows |

Both expose the identifier-exact `cms_source` schema, so SQL written
against one runs against the other.

## What's research-worthy

1. **Era-aware schema-drift handling** — a single generator emits all
   three CMS eras with byte-exact identifiers from a single source
   of truth.
2. **Hybrid-source fusion** — Python random + Synthea-RIF transform
   + targeted oncology overlay → schema-coherent DB with referential-
   integrity tests across the seam.
3. **Synthetic-real defense-in-depth parity** — same partition
   filters, indexes, and cursor pattern as the institutional
   production server, so an agent passing synthetic cannot fail
   production for partition reasons.
4. **The Medicaid TAF synthetic-data gap is a publishable
   contribution.** No public synthetic Medicaid dataset exists today.
   Researchers either use real PHI or hand-roll synthetic. A Synthea
   TAF exporter validated against an institutional schema would be a
   directly citable short paper.

## Five discrete deliverables that can be cited individually

1. [`cohort_identification/`](../cohort_identification/) — public-data PheWAS / ICD / HCPCS / NDC reference loader with the 3-step disease-code recipe.
2. [`gen_ddl.py`](../synthetic_data/gen_ddl.py) + [`columns_formats.csv`](../synthetic_data/columns_formats.csv) — era-aware schema-crosswalk DDL generator (MySQL + SQLite).
3. [`load_rif.py`](../synthetic_data/load_rif.py) + [`ssa_state_crosswalk.py`](../synthetic_data/ssa_state_crosswalk.py) — Synthea RIF → TAF transformer (the publishable "TAF exporter").
4. [`knowledge/constraints.py`](../knowledge/constraints.py) + [`agents/tools/mysql_tools.py`](../agents/tools/mysql_tools.py) — partition-filter Critic + statement-timeout-with-`KILL` tool layer; reusable HIPAA-style guardrails for any agent-on-claims-DB project.
5. [`tests/test_synthetic_db.py`](../synthetic_data/tests/test_synthetic_db.py) — 25-test compliance harness that any future synthetic CMS dataset can be validated against.

## Where to get the public input datasets

Both inputs are public domain (CMS), redistributable, but distributed
from landing pages that hand-roll download links per visit, so they
can't be curl'd directly. Follow the steps in
[`../synthetic_data/download_synthetic_data.sh`](../synthetic_data/download_synthetic_data.sh)
or:

- **DE-SynPUF 2008–2010 Sample 1** (~1.2 GB): https://www.cms.gov/data-research/statistics-trends-and-reports/medicare-claims-synthetic-public-use-files/cms-2008-2010-data-entrepreneurs-synthetic-public-use-file-de-synpuf
  - Save to `synthetic_data/de_synpuf_2008_2010/` (unzipped CSVs).
  - The build only strictly needs `DE1_0_2008_Beneficiary_Summary_File_Sample_1.csv`.
- **CMS Synthetic RIF 2023** (~1 GB): https://data.cms.gov/collection/synthetic-medicare-enrollment-fee-for-service-claims-and-prescription-drug-events
  - Save to `synthetic_data/synthetic_rif_2023/` as `beneficiary_YYYY.csv`, `inpatient.csv`, `outpatient.csv`, `pde.csv`.

The build script ([`build_cms_source.sh`](../synthetic_data/build_cms_source.sh))
preflight-checks these and prints a clear error if either is missing.

## Pointers

- Build script: [`synthetic_data/build_cms_source.sh`](../synthetic_data/build_cms_source.sh)
- Compliance tests: [`synthetic_data/tests/test_synthetic_db.py`](../synthetic_data/tests/test_synthetic_db.py)
- Known gaps and overlay rationale: [`synthetic_data/KNOWN_GAPS.md`](../synthetic_data/KNOWN_GAPS.md)
- HIPAA model: [docs/hipaa.md](hipaa.md)
