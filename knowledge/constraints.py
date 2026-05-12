"""
CMS Medicaid Diabetes Cohort — Institutional System Constraints & SQL Rules
==========================================================================
Used by the Critic / Validator node to check generated SQL for correctness
before execution. All rules are derived from the gold-standard SQL and the
institutional Medicaid MySQL server's partition-enforcement requirements.
"""

from __future__ import annotations

# ---------------------------------------------------------------------------
# 1. Partition Filter (CRITICAL — institutional servers kill unpartitioned scans)
# ---------------------------------------------------------------------------

PARTITION_FILTER_RULE = """
Every SELECT against a cms_source source table MUST include BOTH:
  (a) a state_key / STATE_KEY equality filter, AND
  (b) a year filter: YR_NUM (ERA1/ERA2) or RFRNC_YR (TAF/ERA3)
The correct pattern is a stored-procedure cursor that iterates over
  cms_source.state_codes × cms_source.data_years
and issues one filtered INSERT per (state, year) pair.

Violation: any query on inpatient / inpatient1315 / other_therapy /
other_therapy1315 / taf_inpatient_header / taf_other_services_header
that lacks both filters will be automatically killed by the institutional
production server.
"""

# Columns that satisfy the partition filter per source table
PARTITION_COLUMNS: dict[str, dict[str, str]] = {
    "inpatient":               {"state": "state_key",  "year": "YR_NUM"},
    "inpatient1315":           {"state": "state_key",  "year": "YR_NUM"},
    "other_therapy":           {"state": "state_key",  "year": "YR_NUM"},
    "other_therapy1315":       {"state": "state_key",  "year": "YR_NUM"},
    "taf_inpatient_header":    {"state": "STATE_KEY",  "year": "RFRNC_YR"},
    "taf_other_services_header":{"state":"STATE_KEY",  "year": "RFRNC_YR"},
}

# ---------------------------------------------------------------------------
# 2. Stored Procedure / Cursor Pattern
# ---------------------------------------------------------------------------

CURSOR_PATTERN_RULE = """
Extraction queries against CMS source tables MUST use a cursor-based loop:
  1. DELIMITER $$
  2. CREATE PROCEDURE proc_name()
     BEGIN
       DECLARE st_key INT;
       DECLARE st_cd  VARCHAR(2);
       DECLARE year_num INT;
       DECLARE done BOOLEAN DEFAULT 0;
       DECLARE cur1 CURSOR FOR
           SELECT sc.state_key, sc.state_code, dy.year_num
           FROM cms_source.state_codes sc, cms_source.data_years dy
           ORDER BY sc.state_code, dy.year_num;
       DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
       OPEN cur1;
       read_loop: LOOP
           FETCH cur1 INTO st_key, st_cd, year_num;
           IF done THEN LEAVE read_loop; END IF;
           INSERT INTO <target_table> (...)
           SELECT ... FROM cms_source.<source_table>
           WHERE state_key = st_key
             AND YR_NUM = year_num   -- or RFRNC_YR for TAF
             AND (<diabetes_filter>);
       END LOOP;
       CLOSE cur1;
     END$$
  3. DELIMITER ;
  4. CALL proc_name();

The logmessage() stub is a no-op on the institutional server; include if present in the gold standard.
"""

# ---------------------------------------------------------------------------
# 3. Column Name Rules (exact casing from ground-truth SQL)
# ---------------------------------------------------------------------------

EXACT_COLUMN_NAMES: dict[str, list[str]] = {
    "inpatient / inpatient1315 source": [
        "patient_id", "BENE_ID", "STATE_CD", "state_key", "YR_NUM",
        "EL_DOB", "EL_SEX_CD", "EL_RACE_ETHNCY_CD",
        "srvc_bgn_dt", "srvc_end_dt",
        "DIAG_CD_1", "DIAG_CD_2", "DIAG_CD_3", "DIAG_CD_4", "DIAG_CD_5",
        "DIAG_CD_6", "DIAG_CD_7", "DIAG_CD_8", "DIAG_CD_9",
    ],
    "other_therapy / other_therapy1315 source": [
        "patient_id", "BENE_ID", "STATE_CD", "state_key", "YR_NUM",
        "EL_DOB", "EL_SEX_CD", "EL_RACE_ETHNCY_CD",
        "srvc_bgn_dt", "srvc_end_dt",
        "DIAG_CD_1", "DIAG_CD_2",
    ],
    "taf_inpatient_header source": [
        "PATIENT_ID", "BENE_ID", "STATE_CD", "STATE_KEY", "RFRNC_YR", "BIRTH_DT",
        "srvc_bgn_dt", "srvc_end_dt",
        "DGNS_CD_1", "DGNS_CD_2", "DGNS_CD_3", "DGNS_CD_4", "DGNS_CD_5", "DGNS_CD_6",
        "DGNS_CD_7", "DGNS_CD_8", "DGNS_CD_9", "DGNS_CD_10", "DGNS_CD_11", "DGNS_CD_12",
    ],
    "taf_other_services_header source": [
        "PATIENT_ID", "BENE_ID", "STATE_CD", "STATE_KEY", "RFRNC_YR", "BIRTH_DT",
        "srvc_bgn_dt", "srvc_end_dt",
        "DGNS_CD_1", "DGNS_CD_2",
    ],
    "all_combine / All_Selected_state": [
        "PATIENT_ID", "BENE_ID", "STATE_CD", "STATE_KEY", "YR_NUM", "BIRTH_DT",
        "srvc_bgn_dt", "srvc_end_dt",
        "DIAG_CD_1", "DIAG_CD_2", "DIAG_CD_3", "DIAG_CD_4", "DIAG_CD_5", "DIAG_CD_6",
        "DIAG_CD_7", "DIAG_CD_8", "DIAG_CD_9", "DIAG_CD_10", "DIAG_CD_11", "DIAG_CD_12",
    ],
}

COMMON_MISTAKES: list[str] = [
    "Using DIAG_CD_ for TAF tables (should be DGNS_CD_)",
    "Using DGNS_CD_ for ERA1/2 tables (should be DIAG_CD_)",
    "Using YR_NUM for TAF tables (should be RFRNC_YR)",
    "Using RFRNC_YR for ERA1/2 tables (should be YR_NUM)",
    "Using EL_DOB for TAF tables (should be BIRTH_DT)",
    "Using patient_id (lowercase) for TAF tables (should be PATIENT_ID uppercase)",
    "Using state_key (lowercase) for TAF tables (should be STATE_KEY uppercase)",
    "Querying `ICD code` without backtick quotes (table name contains a space)",
    "Omitting the state_key/STATE_KEY filter on any cms_source table",
    "Omitting the year filter on any cms_source table",
    "Assuming EL_SEX_CD / EL_RACE_ETHNCY_CD exist in TAF tables (they do not)",
    "Expecting all_combine to have sex/race columns (they are dropped in Step 3)",
]

# ---------------------------------------------------------------------------
# 4. Diabetes Filter Logic
# ---------------------------------------------------------------------------

DIABETES_FILTER_RULE = """
A claim qualifies as diabetic if ANY diagnosis column matches:
  (a) ICD-9 codes  → column IN (SELECT codes FROM icd_9_cm)
      [used for ERA1 2005-2012 and ERA2 2013-2015 which stored ICD-9 codes]
  (b) ICD-10 LIKE  → column LIKE 'E08%' OR 'E09%' OR 'E11%' OR 'E13%'
                                 OR 'O241%' OR 'O243%' OR 'O248%'
      [used for TAF 2016-2018 which stored ICD-10 codes]

Both conditions are checked for ERA1/2 inpatient (since some records may
already contain ICD-10 codes even in MAX era — ground-truth SQL applies both).
All 9 (inpatient ERA1/2) or 2 (outpatient) or 12 (TAF inpatient) diagnosis
columns must be checked with OR logic.
"""

# ---------------------------------------------------------------------------
# 5. 24-Month Incident Criterion
# ---------------------------------------------------------------------------

TWO_YEAR_RULE = """
A patient counts as an incident diabetes case if they have at least 2 claims
with diabetes diagnosis codes within a 730-day (2-year) window.

Implementation (Step 4, Loop_all_in_two_years.sql):
  - Cursor ordered by (patient_id, srvc_bgn_DT)
  - For consecutive rows with the same patient_id AND same state_CD:
      IF DATEDIFF(current_srvc_bgn_DT, last_srvc_bgn_DT) <= 730
          THEN appears_within_2_years = 1

Current limitation: the ground-truth procedure is hardcoded to state_CD='GA'.
A version covering all 7 SE states has not been committed to the repository.
"""

# ---------------------------------------------------------------------------
# 6. Step 5 (Consolidation) Known Gap
# ---------------------------------------------------------------------------

STEP5_GAP = """
step5_consolidate/ references two tables that are never created by this pipeline:
  - lung_inpatient_records   (used in step_2.sql, step_5.sql)
  - lung_patient_records     (used in step_2.sql, combined_inpatient.sql)

These are legacy names from a prior lung-disease version of the pipeline.
The bridge from All_Selected_state / test_temp_all_in_two_years_GA to
lung_inpatient_records / lung_patient_records is NOT documented.

Do NOT generate code that assumes these tables exist unless explicitly told
how they are populated.  For the toy-DB runner, lung_patient_records is
materialised as a CTAS from the Step-2 extraction tables.
"""

# ---------------------------------------------------------------------------
# 7. Critic Static Check Functions
# ---------------------------------------------------------------------------

import re

def check_partition_filter(sql: str, source_table: str) -> list[str]:
    """
    Return list of violation messages if `sql` queries `source_table`
    without the required partition filters.
    """
    violations = []
    sql_lower = sql.lower()
    if source_table.lower() not in sql_lower:
        return violations  # table not referenced, skip

    pc = PARTITION_COLUMNS.get(source_table, {})
    state_col = pc.get("state", "state_key").lower()
    year_col  = pc.get("year",  "yr_num").lower()

    if state_col not in sql_lower:
        violations.append(
            f"Missing partition filter: '{pc.get('state')}' not found in query on {source_table}"
        )
    if year_col not in sql_lower:
        violations.append(
            f"Missing partition filter: '{pc.get('year')}' not found in query on {source_table}"
        )
    return violations


def check_column_names(sql: str) -> list[str]:
    """
    Return list of suspected column-name mistakes by checking known wrong
    patterns against the SQL text.
    """
    violations = []
    sql_lower = sql.lower()

    # TAF tables should not use DIAG_CD_
    for taf_tbl in ("taf_inpatient_header", "taf_other_services_header",
                    "re_all_taf_inpatient", "re_all_other_services"):
        if taf_tbl in sql_lower and re.search(r'\bdiag_cd_\d', sql_lower):
            violations.append(
                f"Possible wrong column: DIAG_CD_ found in context of TAF table "
                f"({taf_tbl}); should be DGNS_CD_"
            )

    # ERA1/2 tables should not use DGNS_CD_
    for era_tbl in ("inpatient", "other_therapy"):
        if re.search(rf'\b{era_tbl}\b', sql_lower) and \
           "taf" not in sql_lower and \
           re.search(r'\bdgns_cd_\d', sql_lower):
            violations.append(
                f"Possible wrong column: DGNS_CD_ found in context of ERA1/2 table "
                f"({era_tbl}); should be DIAG_CD_"
            )

    # ICD code table must be backtick-quoted
    if "icd code" in sql_lower and "`icd code`" not in sql_lower:
        violations.append(
            "Table name `ICD code` contains a space and must be backtick-quoted"
        )

    return violations


def check_all(sql: str, source_tables: list[str] | None = None) -> list[str]:
    """
    Run all static checks on `sql`. Returns a (possibly empty) list of
    violation strings.  Pass source_tables to restrict partition checks.
    """
    all_violations: list[str] = []

    tables = source_tables or list(PARTITION_COLUMNS.keys())
    for tbl in tables:
        all_violations.extend(check_partition_filter(sql, tbl))

    all_violations.extend(check_column_names(sql))
    return all_violations
