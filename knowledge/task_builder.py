"""
Task string builder for the SQL Writer agent.

Combines:
  - Disease profile (disease-specific: ICD codes, table names)
  - Shared skill files (structural: cursor pattern, partition filter rules)

Usage:
    from knowledge.task_builder import build_extraction_task
    from knowledge.diseases import diabetes as disease

    task = build_extraction_task(
        disease=disease,
        source_table="inpatient",
        era="ERA1",
        year_start=2005,
        year_end=2012,
    )
"""
from __future__ import annotations
import os
import types

_SKILLS_DIR = os.path.join(os.path.dirname(__file__), "skills")


def _load_skill(name: str) -> str:
    """Read a skill file from knowledge/skills/{name}.md"""
    path = os.path.join(_SKILLS_DIR, f"{name}.md")
    with open(path, encoding="utf-8") as f:
        return f.read()


# ── Era metadata ──────────────────────────────────────────────────────────────

_ERA_META: dict[str, dict] = {
    "ERA1": {
        "years": (2005, 2012),
        "year_col": "YR_NUM",
        "state_col": "state_key",
        "patient_col": "patient_id",
        "diag_col_prefix": "DIAG_CD_",
        "diag_col_count": 9,   # inpatient; 2 for other_therapy
        "dob_col": "EL_DOB",
    },
    "ERA2": {
        "years": (2013, 2015),
        "year_col": "YR_NUM",
        "state_col": "state_key",
        "patient_col": "patient_id",
        "diag_col_prefix": "DIAG_CD_",
        "diag_col_count": 9,
        "dob_col": "EL_DOB",
    },
    "ERA3": {
        "years": (2016, 2018),
        "year_col": "RFRNC_YR",
        "state_col": "STATE_KEY",
        "patient_col": "PATIENT_ID",
        "diag_col_prefix": "DGNS_CD_",
        "diag_col_count": 12,  # taf_inpatient; 2 for taf_other_services
        "dob_col": "BIRTH_DT",
    },
}

# Source tables that belong to each era
_ERA_SOURCES: dict[str, list[str]] = {
    "ERA1": ["inpatient", "other_therapy"],
    "ERA2": ["inpatient1315", "other_therapy1315"],
    "ERA3": ["taf_inpatient_header", "taf_other_services_header"],
}


def build_extraction_task(
    disease: types.ModuleType,
    source_table: str,
    era: str,
    year_start: int | None = None,
    year_end: int | None = None,
) -> str:
    """
    Build the full task string for one extraction step.

    Parameters
    ----------
    disease     : disease module (e.g. knowledge.diseases.diabetes)
    source_table: CMS source table name (e.g. "inpatient")
    era         : "ERA1" | "ERA2" | "ERA3"
    year_start  : override year start (default: era default)
    year_end    : override year end (default: era default)
    """
    meta = _ERA_META[era]
    ys = year_start if year_start is not None else meta["years"][0]
    ye = year_end   if year_end   is not None else meta["years"][1]

    output_table = disease.OUTPUT_TABLE_MAP[source_table]
    proc_name    = disease.PROCEDURE_MAP[source_table]
    year_col     = meta["year_col"]

    # Disease filter hint — era-appropriate (ERA2 is transitional ICD-9+10)
    if era == "ERA1":
        filter_hint = disease.ICD9_FILTER_HINT
    elif era == "ERA2":
        filter_hint = getattr(disease, "ERA2_FILTER_HINT", disease.ICD9_FILTER_HINT)
    else:  # ERA3
        filter_hint = getattr(disease, "ERA3_FILTER_HINT", disease.ICD10_FILTER_HINT)

    task = f"""\
Task: Extract {disease.DISEASE_NAME} claims from cms_source.{source_table} \
(years {ys}–{ye})
into a new table called {output_table}.
Use a MySQL stored procedure named {proc_name}.

Constraints:
1. PARTITION FILTER (mandatory): every INSERT must filter by a specific \
{meta['state_col']} AND {year_col} pair. Do NOT query the whole table at once.

2. ITERATION LOGIC: the procedure must loop over every (state_key, year_num) combination.
   - cms_source.state_codes has one row per state (columns: state_key INT, state_code CHAR(2))
   - cms_source.data_years  has one row per year  (column: year_num INT)
   - For {era}, only include years {ys}–{ye}.
   - For each (state_key, year_num) pair: INSERT INTO {output_table} ... SELECT ...
     FROM cms_source.{source_table} \
WHERE {meta['state_col']} = <state_key> AND {year_col} = <year_num>
     AND <{disease.DISEASE_NAME} filter>.

3. DISEASE FILTER: {filter_hint}
   Use preview_table to confirm the exact diagnosis column names.

4. MYSQL CURSOR PATTERN (recommended): Use a SINGLE cursor over a CROSS JOIN of
   state_codes and data_years — this avoids MySQL's nested-cursor DONE-flag bug:

     DECLARE cur1 CURSOR FOR
       SELECT sc.state_key, dy.year_num
       FROM cms_source.state_codes sc, cms_source.data_years dy
       WHERE dy.year_num BETWEEN {ys} AND {ye}
       ORDER BY sc.state_key, dy.year_num;
     DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

   If you DO use nested cursors, you MUST declare a SEPARATE done flag for each
   cursor (e.g., done_state INT DEFAULT 0, done_year INT DEFAULT 0) — MySQL's
   CONTINUE HANDLER FOR NOT FOUND sets a shared flag, so the inner cursor
   exhausting can accidentally exit the outer loop.
"""
    return task
