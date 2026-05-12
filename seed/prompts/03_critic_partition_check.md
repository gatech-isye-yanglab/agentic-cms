# Prompt 03 — Critic checks + schema metadata + clinical codes

## Goal

Generate the static-analysis half of the Critic plus the schema and
clinical-code reference files the agent reads at runtime. These are
the "rules of the institutional database" expressed as Python.

## Files to generate

| File | Purpose |
|---|---|
| `knowledge/__init__.py` | Empty marker. |
| `knowledge/schema.json` | Column metadata for the 6 source tables, era differences, intermediate-table shapes, reference tables. **No row data — just schema descriptions.** |
| `knowledge/codes.py` | ICD-9 / ICD-10 / HCPCS reference lists for the diabetes profile, plus target SE states. |
| `knowledge/constraints.py` | The static-analysis Critic: PARTITION_FILTER_RULE, EXACT_COLUMN_NAMES per source table, COMMON_MISTAKES list, DIABETES_FILTER_RULE, TWO_YEAR_RULE, plus three callable check functions. |

## constraints.py — the rule layer

### Section 1: Partition filter rule

The institutional production server kills any query against
`cms_source.*` source tables that lacks both:

- a `state_key` / `STATE_KEY` equality filter (lowercase for MAX era,
  uppercase for TAF era), AND
- a year filter (`YR_NUM` for MAX, `RFRNC_YR` for TAF).

Encode this as a docstring constant `PARTITION_FILTER_RULE`, and as
a per-table dictionary:

```python
PARTITION_COLUMNS: dict[str, dict[str, str]] = {
    "inpatient":                {"state": "state_key", "year": "YR_NUM"},
    "inpatient1315":            {"state": "state_key", "year": "YR_NUM"},
    "other_therapy":            {"state": "state_key", "year": "YR_NUM"},
    "other_therapy1315":        {"state": "state_key", "year": "YR_NUM"},
    "taf_inpatient_header":     {"state": "STATE_KEY", "year": "RFRNC_YR"},
    "taf_other_services_header":{"state": "STATE_KEY", "year": "RFRNC_YR"},
}
```

### Section 2: Exact column names per source table

A dictionary keyed by a human-readable description, mapping to the
exact column list. Used both as documentation for the agent and as a
reference point for `check_column_names`. Example:

```python
EXACT_COLUMN_NAMES: dict[str, list[str]] = {
    "inpatient / inpatient1315 source": [
        "patient_id", "BENE_ID", "STATE_CD", "state_key", "YR_NUM",
        "EL_DOB", "EL_SEX_CD", "EL_RACE_ETHNCY_CD",
        "SRVC_BGN_DT", "SRVC_END_DT",  # uppercase per columns_formats.csv
        "DIAG_CD_1", ..., "DIAG_CD_9",
    ],
    "taf_inpatient_header source": [
        "PATIENT_ID", "BENE_ID", "STATE_CD", "STATE_KEY", "RFRNC_YR", "BIRTH_DT",
        "SRVC_BGN_DT", "SRVC_END_DT",  # uppercase per columns_formats.csv
        "DGNS_CD_1", ..., "DGNS_CD_12",
    ],
    # ...
}
```

### Section 3: Common mistakes list

A list of strings describing the failure modes the agent should
avoid. Examples:

- "Using DIAG_CD_ for TAF tables (should be DGNS_CD_)"
- "Using YR_NUM for TAF tables (should be RFRNC_YR)"
- "Using EL_DOB for TAF tables (should be BIRTH_DT)"
- "Using patient_id (lowercase) for TAF tables (should be PATIENT_ID uppercase)"
- "Querying \`ICD code\` without backtick quotes (table name contains a space)"
- "Omitting the state_key/STATE_KEY filter on any cms_source table"
- "Assuming EL_SEX_CD / EL_RACE_ETHNCY_CD exist in TAF tables (they do not)"

These appear verbatim in the agent's system prompt and the Critic's
feedback messages.

### Section 4: Disease-specific filter rules

Multi-line strings describing:

- `DIABETES_FILTER_RULE`: the ICD-9 IN (subquery) and ICD-10 LIKE-
  pattern matching, when each applies, and the requirement to OR
  across all DIAG_CD_/DGNS_CD_ columns.
- `TWO_YEAR_RULE`: the 24-month / 730-day incident criterion,
  including the GA-only limitation in the current Step 4
  implementation.
- `STEP5_GAP`: the legacy `lung_inpatient_records` /
  `lung_patient_records` table-name leak from a prior pipeline.

### Section 5: Three callable check functions

```python
def check_partition_filter(sql: str, source_table: str) -> list[str]:
    """Return list of violation messages if `sql` queries `source_table`
    without the required partition filters."""

def check_column_names(sql: str) -> list[str]:
    """Return list of suspected column-name mistakes by checking known
    wrong patterns against the SQL text."""

def check_all(sql: str, source_tables: list[str] | None = None) -> list[str]:
    """Run all static checks. Returns a (possibly empty) list of
    violation strings."""
```

Implementation notes:

- `check_partition_filter`: lowercase the SQL, see if `source_table`
  is referenced. If yes, check that the per-table state column AND
  year column appear in the lowercased SQL. Return one violation
  per missing column.
- `check_column_names`: regex-detect TAF tables in the SQL
  (`taf_inpatient_header`, `taf_other_services_header`,
  `re_all_taf_inpatient`, `re_all_other_services`) and flag
  `\bdiag_cd_\d` matches as wrong. Inverse for ERA1/2 tables and
  `\bdgns_cd_\d`. Also flag `icd code` table-name without backtick
  quotes.
- `check_all`: iterate `PARTITION_COLUMNS.keys()` (or the supplied
  subset) calling `check_partition_filter`, then call
  `check_column_names`. Concatenate violations.

## schema.json — what to include

A nested dictionary with these top-level keys:

- `_comment`: one-line description.
- `source_tables`: dict of 6 entries (`inpatient`, `inpatient1315`,
  `other_therapy`, `other_therapy1315`, `taf_inpatient_header`,
  `taf_other_services_header`). Each entry has:
  - `era`: human-readable era label ("MAX 2005-2012", etc.)
  - `type`: `"inpatient"` or `"outpatient"`
  - `years`: list of valid year values
  - `year_column`: `"YR_NUM"` or `"RFRNC_YR"`
  - `patient_id_column`: `"patient_id"` or `"PATIENT_ID"`
  - `columns`: dict of column-name → `{type, note?}`. Mark partition
    keys with `"note": "partition key — MUST filter"`.
  - `diag_columns`: ordered list of diagnosis columns
  - `extraction_table`: the Step-1 output table name (e.g. `Re_all_inpatient`)
  - `extraction_procedure`: the Step-1 stored-procedure name
- `era_differences`: small dict highlighting the per-concept renames
  between eras (`patient_id` casing, `year_column` rename, `dob_column`
  rename, `diag_prefix`, etc.).
- `intermediate_tables`: dict describing tables produced by the
  pipeline (Step-1 outputs, `all_combine`, `All_Selected_state`,
  `temp_all_in_two_years_GA`, `final_patient`).
- `reference_tables`: dict for `icd_9_cm`, `ICD code` (with the
  backtick-quoting note), `HCPCS_Codes`, `state_codes`,
  `data_years`.
- `pipeline_steps`: ordered list of step numbers, folder names, and
  output tables.

This file is read by the Schema Agent (today: inlined into the SQL
Writer's system prompt) to determine correct column names and joins.

## codes.py — diabetes reference lists

Plain Python module with named lists/dicts:

- `ICD9_CODES`: ~29 ICD-9 codes (250.x family + diabetic neuropathy
  3572 + retinopathy 36641, 36201-36207).
- `ICD10_LIKE_PATTERNS`: 7 entries (`E08%`, `E09%`, `E11%`, `E13%`,
  `O241%`, `O243%`, `O248%`).
- `ICD10_LIKE_SQL_TEMPLATE`: a Python string template with `{col}`
  placeholder, used to substitute into SQL fragments.
- `ICD10_TO_ICD9`: a ~100-entry dict mapping common ICD-10 codes back
  to their ICD-9 equivalents (covers Type-1, Type-2, complications,
  cardiovascular, neuropathy, retinopathy, renal, skin/wound,
  musculoskeletal).
- `HCPCS_CODES`: ~55 HCPCS codes (glucose monitoring, insulin,
  insulin pumps, wound care, nutrition, diabetes self-management
  education).
- `TARGET_STATES = ["AL", "FL", "GA", "MS", "NC", "SC", "TN"]`.
- `TARGET_STATES_SQL`: pre-built SQL fragment string with OR'd
  state_cd predicates.
- `ERA_YEARS`: dict mapping era labels to year ranges.

Source of these lists: the gold-standard `pipelines/diabetes/reference/`
SQL files in the full repo. They are validated against
`seed/data/examples/diabetes_codes.json`. Do not hallucinate codes;
if uncertain, copy from the validation target.

## See also

- Full-repo equivalents at `knowledge/{constraints.py, schema.json, codes.py}`.
- Prompt 04 for the structural skill files the agent reads alongside this.
- Prompt 05 for the disease-profile templates that wrap these into a per-disease task.
