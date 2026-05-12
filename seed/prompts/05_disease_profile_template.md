# Prompt 05 — Disease profile template + task builder

## Goal

Generate the disease-swap mechanism: one template Python file that
defines a disease's identity, ICD codes, output table names, and
filter hints; plus a task-builder that wraps the disease profile +
era metadata + skill files into the agent's task string.

This is the abstraction that makes the pipeline reusable. Drop in a
new disease profile, and the same Step-1..5 SQL infrastructure runs
unchanged.

## Files to generate

| File | Purpose |
|---|---|
| `knowledge/diseases/__init__.py` | Comment-only marker file documenting how to import a disease profile. |
| `knowledge/diseases/diabetes.py` | The diabetes profile — the template all other diseases follow. |
| `knowledge/task_builder.py` | Builds the agent task string from a disease module + source table + era. |

## diseases/diabetes.py — the template shape

A disease profile is a flat Python module with these named exports:

```python
DISEASE_NAME: str = "diabetes"

# Reference table names + column the agent joins against
ICD9_TABLE: str = "icd_9_cm"
ICD9_COL: str = "codes"

# Raw code lists (used by seed scripts and reference)
ICD9_CODES: list[str] = ["25000", "25010", ...]
ICD10_LIKE_PATTERNS: list[str] = ["E08%", "E09%", "E11%", "E13%", "O241%", "O243%", "O248%"]

# Output table per source table — Re_all_*, Re_All_taf_*
OUTPUT_TABLE_MAP: dict[str, str] = {
    "inpatient":                 "Re_all_inpatient",
    "inpatient1315":             "Re_all_inpatient1315",
    "other_therapy":             "Re_all_other_therapy",
    "other_therapy1315":         "Re_all_other_therapy1315",
    "taf_inpatient_header":      "Re_All_taf_inpatient_header",
    "taf_other_services_header": "Re_All_other_services_header",
}

# Stored procedure name per source table
PROCEDURE_MAP: dict[str, str] = {
    "inpatient":                 "Re_all_inpatient_loop",
    # ... matching pattern
}

# Per-era filter hints (multi-line strings injected into agent task)
ICD9_FILTER_HINT: str = (
    "A claim qualifies if ANY DIAG_CD_n column (DIAG_CD_1..9) matches a code "
    f"in cms_source.{ICD9_TABLE} (column: {ICD9_COL}). "
    f"Use: DIAG_CD_n IN (SELECT {ICD9_COL} FROM cms_source.{ICD9_TABLE})"
)

ERA2_FILTER_HINT: str = (
    "ICD-9 OR ICD-10 LIKE patterns; ERA2 records may contain either. "
    "Apply BOTH checks (OR'd together) for every DIAG_CD_ column."
)

ERA3_FILTER_HINT: str = (
    "DGNS_CD_1..12 (not DIAG_CD_). ICD-10 LIKE primary; ICD-9 IN secondary. "
    "Apply BOTH (OR'd together) for every DGNS_CD_ column."
)

ICD10_FILTER_HINT = ERA3_FILTER_HINT  # back-compat alias
```

## task_builder.py — what it does

`build_extraction_task(disease, source_table, era, year_start=None,
year_end=None) -> str` returns a multi-paragraph task string the
agent can read directly.

Internal era metadata:

```python
_ERA_META: dict[str, dict] = {
    "ERA1": {
        "years": (2005, 2012),
        "year_col": "YR_NUM",
        "state_col": "state_key",
        "patient_col": "patient_id",
        "diag_col_prefix": "DIAG_CD_",
        "diag_col_count": 9,
        "dob_col": "EL_DOB",
    },
    "ERA2": { ... 2013-2015, same shape as ERA1 ... },
    "ERA3": {
        "years": (2016, 2018),
        "year_col": "RFRNC_YR",
        "state_col": "STATE_KEY",
        "patient_col": "PATIENT_ID",
        "diag_col_prefix": "DGNS_CD_",
        "diag_col_count": 12,
        "dob_col": "BIRTH_DT",
    },
}
```

The task string this function builds has this skeleton:

```
Task: Extract {DISEASE_NAME} claims from cms_source.{source_table} (years {ys}–{ye})
into a new table called {output_table}.
Use a MySQL stored procedure named {proc_name}.

Constraints:
1. PARTITION FILTER (mandatory): every INSERT must filter by a specific
   {state_col} AND {year_col} pair. Do NOT query the whole table at once.

2. ITERATION LOGIC: the procedure must loop over every (state_key, year_num) combination.
   - cms_source.state_codes has one row per state (state_key INT, state_code CHAR(2))
   - cms_source.data_years has one row per year (year_num INT)
   - For {era}, only include years {ys}–{ye}.
   - For each (state_key, year_num) pair: INSERT INTO {output_table} ... SELECT ...
     FROM cms_source.{source_table} WHERE {state_col} = <state_key> AND {year_col} = <year_num>
     AND <{disease} filter>.

3. DISEASE FILTER: {filter_hint}
   Use preview_table to confirm the exact diagnosis column names.

4. MYSQL CURSOR PATTERN (recommended): Use a SINGLE cursor over a CROSS JOIN of
   state_codes and data_years — this avoids MySQL's nested-cursor DONE-flag bug:
   <SQL excerpt as in extraction_cursor.md>

   If you DO use nested cursors, you MUST declare a SEPARATE done flag for each
   cursor (done_state INT DEFAULT 0, done_year INT DEFAULT 0)...
```

The function selects `filter_hint`:
- ERA1 → `disease.ICD9_FILTER_HINT`
- ERA2 → `getattr(disease, "ERA2_FILTER_HINT", disease.ICD9_FILTER_HINT)`
- ERA3 → `getattr(disease, "ERA3_FILTER_HINT", disease.ICD10_FILTER_HINT)`

## How to add a new disease

Document this in `diseases/__init__.py`:

```python
# Disease profiles — import the one you need:
#   from knowledge.diseases import diabetes
#   from knowledge.diseases import lung_cancer
#
# To add a new disease: copy diabetes.py, rename to <disease>.py,
# replace ICD9_CODES / ICD10_LIKE_PATTERNS / OUTPUT_TABLE_MAP /
# PROCEDURE_MAP / *_FILTER_HINT with the new disease's values, and
# update DISEASE_NAME. The pipeline runs unchanged.
```

## Validation against examples

The diabetes profile must produce code lists that match
`seed/data/examples/diabetes_codes.json` exactly. If `ICD9_CODES`,
`ICD10_LIKE_PATTERNS`, or `HCPCS_CODES` (in `knowledge/codes.py`,
prompt 03) deviate from the validation target, the bootstrap has
failed at this prompt. Fix and re-run.

## See also

- Full-repo equivalents at `knowledge/{task_builder.py, diseases/diabetes.py, diseases/__init__.py}`.
- `seed/data/examples/diabetes_codes.json` — the validation target for diabetes code lists.
- Prompt 06 for the per-disease pipelines that this profile parameterizes.
