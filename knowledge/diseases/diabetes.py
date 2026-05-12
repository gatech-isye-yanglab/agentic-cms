"""
Disease profile: Diabetes cohort extraction.

Swap this file (or import a different one) to run the same pipeline for a
different disease — only codes, table names, and filter logic change.

Shared pipeline structure (cursor pattern, partition filter, combine step,
state filter, 2-year incident criterion) is defined in knowledge/skills/ and
is reused across all diseases.
"""
from __future__ import annotations

# ── Identity ──────────────────────────────────────────────────────────────────

DISEASE_NAME = "diabetes"

# ── ICD-9 reference table (pre-loaded into cms_source) ───────────────────────
# The agent uses:  DIAG_CD_n IN (SELECT codes FROM {ICD9_TABLE})
ICD9_TABLE = "icd_9_cm"
ICD9_COL   = "codes"

# Raw ICD-9 codes (used by seed scripts and for reference)
ICD9_CODES: list[str] = [
    "25000", "25010", "25020", "25030", "25040", "25050", "25060", "25070", "25080", "25090",
    "25002", "25012", "25022", "25032", "25042", "25052", "25062", "25072", "25082", "25092",
    "3572",
    "36641", "36201", "36202", "36203", "36204", "36205", "36206", "36207",
]

# ── ICD-10 LIKE patterns (ERA3 / TAF 2016-2018) ──────────────────────────────
# The agent uses:  DGNS_CD_n LIKE 'E08%' OR DGNS_CD_n LIKE 'E11%' ...
ICD10_LIKE_PATTERNS: list[str] = [
    "E08%", "E09%", "E11%", "E13%", "O241%", "O243%", "O248%",
]

# ── Output table names per source table ───────────────────────────────────────
# These are the "Re_all_*" tables produced by the extraction step.
# The combine step (step 2) unions these tables regardless of disease.
OUTPUT_TABLE_MAP: dict[str, str] = {
    "inpatient":                 "Re_all_inpatient",
    "inpatient1315":             "Re_all_inpatient1315",
    "other_therapy":             "Re_all_other_therapy",
    "other_therapy1315":         "Re_all_other_therapy1315",
    "taf_inpatient_header":      "Re_All_taf_inpatient_header",
    "taf_other_services_header": "Re_All_other_services_header",
}

# ── Stored procedure names ────────────────────────────────────────────────────
PROCEDURE_MAP: dict[str, str] = {
    "inpatient":                 "Re_all_inpatient_loop",
    "inpatient1315":             "Re_all_inpatient1315_loop",
    "other_therapy":             "Re_all_other_therapy_loop",
    "other_therapy1315":         "Re_all_other_therapy1315_loop",
    "taf_inpatient_header":      "Re_All_taf_inpatient_loop",
    "taf_other_services_header": "Re_All_other_services_loop",
}

# ── Per-era filter hints (injected into agent task description) ───────────────

# ERA1 (2005-2012): ICD-9 codes only — stored in icd_9_cm reference table
ICD9_FILTER_HINT = (
    "A claim qualifies if ANY DIAG_CD_n column (DIAG_CD_1..9) matches a code "
    f"in cms_source.{ICD9_TABLE} (column: {ICD9_COL}). "
    f"Use: DIAG_CD_n IN (SELECT {ICD9_COL} FROM cms_source.{ICD9_TABLE})"
)

# ERA2 (2013-2015): transitional — records may contain ICD-9 or ICD-10 codes.
# Ground truth uses BOTH checks OR'd together on each DIAG_CD_ column.
ERA2_FILTER_HINT = (
    "A claim qualifies if ANY DIAG_CD_n column (DIAG_CD_1..9) matches "
    f"EITHER ICD-9 codes: DIAG_CD_n IN (SELECT {ICD9_COL} FROM cms_source.{ICD9_TABLE}) "
    "OR ICD-10 LIKE patterns: DIAG_CD_n LIKE 'E08%' OR DIAG_CD_n LIKE 'E09%' OR "
    "DIAG_CD_n LIKE 'E11%' OR DIAG_CD_n LIKE 'E13%' OR DIAG_CD_n LIKE 'O241%' OR "
    "DIAG_CD_n LIKE 'O243%' OR DIAG_CD_n LIKE 'O248%'. "
    "Apply BOTH checks (OR'd together) for every DIAG_CD_ column."
)

# ERA3 (2016-2018): TAF era — diagnosis columns are DGNS_CD_1..12 (not DIAG_CD_).
# ICD-10 LIKE is primary; ICD-9 IN is also applied for completeness.
ERA3_FILTER_HINT = (
    "A claim qualifies if ANY DGNS_CD_n column (DGNS_CD_1..12) matches "
    "EITHER ICD-10 LIKE patterns: DGNS_CD_n LIKE 'E08%' OR DGNS_CD_n LIKE 'E09%' OR "
    "DGNS_CD_n LIKE 'E11%' OR DGNS_CD_n LIKE 'E13%' OR DGNS_CD_n LIKE 'O241%' OR "
    "DGNS_CD_n LIKE 'O243%' OR DGNS_CD_n LIKE 'O248%' "
    f"OR ICD-9 codes: DGNS_CD_n IN (SELECT {ICD9_COL} FROM cms_source.{ICD9_TABLE}). "
    "Apply BOTH checks (OR'd together) for every DGNS_CD_ column."
)

# Kept for backward compatibility
ICD10_FILTER_HINT = ERA3_FILTER_HINT
