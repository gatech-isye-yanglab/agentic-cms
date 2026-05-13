# Synthetic CMS Database — Build & Test

This folder contains everything needed to generate a synthetic CMS claims
database whose schema exactly mirrors a real institutional Medicaid MySQL
warehouse. It is the sandbox the LLM agent runs against during development
— no PHI exposure, freely shareable.

## Tier 2a architecture (as of 2026-04-22)

The synthetic build is a **hybrid**: `gen_data.py` supplies the MAX era + meta-tables from random Python draws, `load_rif.py` overwrites the TAF-era tables with realistic Synthea-generated claims from [CMS Synthetic RIF 2023](https://data.cms.gov/collection/synthetic-medicare-enrollment-fee-for-service-claims-and-prescription-drug-event), and a thin Python overlay inside `load_rif.py` injects oncology HCPCS J/C codes (which RIF doesn't model) for the lung-cancer cohort Synthea did generate. See `KNOWN_GAPS.md` for the motivation.

**Orchestrate the whole thing with `bash build_cms_source.sh`.**

## What's here

| File | Purpose |
|---|---|
| `columns_formats.csv` | Source of truth. Institutional schema export — 21 tables, 2,533 columns. Do not hand-edit. Provenance: column metadata only (no data), exported from a real CMS Medicaid MySQL warehouse to enable schema-faithful synthetic generation. |
| `gen_ddl.py` | Parses `columns_formats.csv` → emits `schema_mysql.sql` and `schema_sqlite.sql`. |
| `schema_mysql.sql` / `schema_sqlite.sql` | 21 `CREATE TABLE`s, auto-generated. |
| `gen_data.py` | **Tier 1 generator.** Python-only random draws. Supplies MAX-era tables + meta-tables + initial TAF-era stubs (which Tier 2a overwrites). Still used end-to-end if you don't want the RIF step. |
| `load_rif.py` | **Tier 2a loader.** Transforms CMS Synthetic RIF 2023 (pipe-delimited, Medicare Part A/B/D) into our schema-faithful TAF tables, with SSA → postal state-code translation and a Python oncology-HCPCS overlay for the lung-cancer cohort. |
| `ssa_state_crosswalk.py` | SSA state-code (`'01'`) → USPS postal (`'AL'`) map. Used by `load_rif.py`. |
| `build_cms_source.sh` | **Orchestrator.** Runs `gen_data.py` → `load_rif.py` → `load_mysql.sql` → pytest. The one command you typically need. |
| `synthetic_rif_2023/` | Raw CMS RIF CSVs (1 GB, 8 claim types, 11 enrollment years). Input only; not modified. |
| `de_synpuf_2008_2010/` | Legacy DE-SynPUF — only `DESYNPUF_ID` strings are used (as BENE_ID material in `gen_data.py`). Not loaded as claim data. |
| `synthetic_db.sqlite` | SQLite build produced by `gen_data.py` (~184 MB, ~116k beneficiaries). Used by `tests/`. |
| `csv/` | Per-table CSVs consumed by the MySQL loader. Populated by `gen_data.py` then TAF tables overwritten by `load_rif.py`. |
| `load_mysql.sql` | `LOAD DATA LOCAL INFILE` for all 21 tables. |
| `seed_mysql.py` | Pure-Python fallback loader (no `--local-infile=1` needed). |
| `tests/test_synthetic_db.py` | 25 integration tests — schema, referential integrity, partition filters, diabetes-pipeline semantics. |
| `KNOWN_GAPS.md` | Running punch-list of synthetic-data gaps the generator team should work on. |

## Reproduce from scratch — Tier 2a (recommended)

```bash
# Does everything: gen_data (MAX + meta) → load_rif (TAF from Synthea RIF
# + oncology HCPCS overlay) → load_mysql → pytest
bash build_cms_source.sh
```

Takes ~2.5 min. Leaves `cms_source` populated with:
- MAX-era tables (2005-2015): from `gen_data.py` random draws, ~116k Python-synthesized beneficiaries
- TAF-era tables (2016-2023): from RIF, ~9k Synthea-generated beneficiaries with realistic disease progression, demographics, and prescription events
- `taf_other_services_line.LINE_PRCDR_CD`: RIF values + oncology J/C code overlay for beneficiaries Synthea assigned a lung-cancer ICD

## Reproduce from scratch — Tier 1 (Python only, no RIF)

```bash
# 1. Regenerate schema from the institutional schema export
python3 gen_ddl.py

# 2. Generate synthetic data
#    - Writes synthetic_db.sqlite AND csv/*.csv
#    - "--n-patients all" uses every DESYNPUF_ID in the bootstrap pool.
python3 gen_data.py \
    --sqlite synthetic_db.sqlite \
    --csv ./csv \
    --n-patients all

# 3. Smoke-test
python3 -m pytest tests/ -v
```

## Load into MySQL on a developer laptop

```bash
# Option A — LOAD DATA LOCAL INFILE (fastest; needs server flag)
mysql -u root -p --local-infile=1 < schema_mysql.sql
mysql -u root -p --local-infile=1 cms_source < load_mysql.sql

# Option B — Python batched INSERTs (slower; no server flag)
mysql -u root -p < schema_mysql.sql
python3 seed_mysql.py \
    --host 127.0.0.1 --user root --password 'secret' \
    --database cms_source --csv-dir ./csv
```

MySQL Workbench gotcha: bump *Connections → Advanced → DBMS connection
read timeout* to 600 s, same as the institutional MySQL connection.
Otherwise the long `LOAD DATA` will drop mid-load.

## Design decisions

**Why SQLite as the canonical build artifact?** Portable (no server to
run), and the agent's SQL Writer can use the same SQL dialect the
institutional MySQL accepts *for the queries the agent generates*. We
still ship MySQL DDL and loaders for fidelity testing on an actual
MySQL instance.

**Why regenerate instead of checking in data?** The generator is seeded
(`--seed 42` by default) and deterministic. A 184 MB SQLite DB is not
something we want in git; the recipe to rebuild it is. Raw CSVs are
also regenerated.

**Why exact column-name preservation?** The institutional schema uses
mixed-case identifiers (`STATE_KEY` vs `state_key`, `RFRNC_YR` vs
`YR_NUM`) that differ across eras. The agent will produce SQL referencing
these names; any mismatch breaks deployment. `gen_ddl.py` copies names
verbatim from `columns_formats.csv`.

**Cohort seeding strategy** — the generator allocates patients into
buckets designed to exercise the diabetes-pipeline logic:

| Bucket | % | What the agent should find |
|---|---|---|
| `positive` | 40 | 2+ qualifying diabetes claims <730 days apart in an SE state → keep |
| `single` | 20 | 1 qualifying claim → exclude (fails 24-month rule) |
| `long_gap` | 15 | 2 claims but >730 days apart → exclude |
| `wrong_state` | 10 | Claims outside AL/FL/GA/MS/NC/SC/TN → excluded by Step 3 |
| `no_diabetes` | 10 | Non-diabetes codes only → no cohort hits |
| `ambiguous` | 5 | Contradictory demographics (min ≠ max DOB/sex) → flagged by Step 8 |

Era assignment (MAX vs MAX-1315 vs TAF) is independent of bucket, so
each test condition has examples in all three schema eras.

## The FUSE/virtiofs + SQLite quirk (containerized environments only)

Some containerized FUSE/virtiofs mounts don't implement SQLite's POSIX
file locking. Two consequences when the build runs on such a mount:

1. `gen_data.py` may need to write the SQLite DB to `/tmp/synthetic_db.sqlite`
   and copy it into the workspace — writing directly to the mount can
   give `disk I/O error`.
2. `tests/test_synthetic_db.py` opens the DB with
   `sqlite3.connect(f"file:{path}?mode=ro&immutable=1", uri=True)` so
   SQLite skips lock acquisition. A bare `sqlite3.connect(path)` will
   silently truncate the file to 0 bytes on such a mount.

On a developer laptop neither workaround is necessary — this is purely
a containerized-FS artifact, documented so the pattern doesn't look weird.

## File-size policy

| File | Size | Tracked? |
|---|---|---|
| `synthetic_db.sqlite` | ~184 MB | **No** — regenerate with `gen_data.py` |
| `csv/*.csv` | ~157 MB total | **No** — regenerate with `gen_data.py` |
| `schema_*.sql` | <100 KB | Yes |
| `gen_*.py`, `seed_mysql.py`, `load_mysql.sql` | <100 KB | Yes |
| `columns_formats.csv` | ~215 KB | Yes |

`.gitignore` excludes the large generated artifacts. They are
deterministic functions of the tracked source.
