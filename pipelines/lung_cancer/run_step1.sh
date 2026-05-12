#!/usr/bin/env bash
# run_step1.sh — execute the lung-cancer Step 1 (extraction) against the
# synthetic `cms_source` + `phewas` MySQL DBs. Derived tables land in
# `lung_cancer_pipeline`.
#
# Scope: Step 1 only. Steps 2–5 have structural gaps (undefined
# entire_records_*, patient_for_all_records_srt, immuno_and_chemo_id,
# sickness, 2016-era single_row_table_2016 / *_table_2016_v3) that need
# new SQL — see WORKFLOW_REVIEW.md § Phase B.
#
# Prereqs:
#   1. cms_source loaded (see ../../synthetic_data/)
#   2. phewas loaded   (see ../../cohort_identification/load_phewas_mysql.sh)
#
# Usage:  bash run_step1.sh
#         DB_USER=foo DB_PASS=bar bash run_step1.sh

set -eo pipefail

DB_USER=${DB_USER:-root}
DB_HOST=${DB_HOST:-127.0.0.1}
DB_NAME=${DB_NAME:-lung_cancer_pipeline}
DB_PASS=${DB_PASS:-}

MYSQL=(mysql -u "$DB_USER" -h "$DB_HOST")
if [[ -n "$DB_PASS" ]]; then
    MYSQL+=("-p$DB_PASS")
fi

cd "$(dirname "$0")"

run() {
    local label="$1"
    local path="$2"
    echo "=== $label ==="
    # sed normalises ' --' → '--' so the mysql client recognises DELIMITER
    # when reading from stdin (diabetes pipeline had the same quirk).
    # SET sql_mode='' relaxes NO_ZERO_DATE for 0000-00-00 sentinels.
    { echo "SET SESSION sql_mode = '';"; sed 's/^[[:space:]]*--/--/' "$path"; } \
      | "${MYSQL[@]}" "$DB_NAME"
}

# Reset scratch DB. utf8mb4_unicode_ci matches cms_source.
"${MYSQL[@]}" -e "
DROP DATABASE IF EXISTS $DB_NAME;
CREATE DATABASE $DB_NAME DEFAULT CHARACTER SET utf8mb4 DEFAULT COLLATE utf8mb4_unicode_ci;"

# Reference tables first (derived from phewas + hardcoded HCPCS lists).
run "reference/build_reference_tables"   reference/build_reference_tables.sql

# Step 1 extraction — four parallel procedures.
run "step1/lung_cohort_TAF"               step1_extraction/lung_cohort_TAF.sql
run "step1/exposure_chemo_immuno_TAF"     step1_extraction/exposure_chemo_immuno_TAF.sql
run "step1/outcome_autoimmune_TAF"        step1_extraction/outcome_autoimmune_TAF.sql

echo
echo "=== Row counts ==="
"${MYSQL[@]}" "$DB_NAME" -e "
SELECT 'ICD910_lung_cancer_codes', COUNT(*) FROM ICD910_lung_cancer_codes UNION ALL
SELECT 'chemo_cpt_codes',          COUNT(*) FROM chemo_cpt_codes          UNION ALL
SELECT 'immuno_cpt_codes',         COUNT(*) FROM immuno_cpt_codes         UNION ALL
SELECT 'autoimmune_icd',           COUNT(*) FROM autoimmune_icd           UNION ALL
SELECT 'lung_inpatient_records_orig', COUNT(*) FROM lung_inpatient_records_orig UNION ALL
SELECT 'lung_ospatient_records_orig', COUNT(*) FROM lung_ospatient_records_orig UNION ALL
SELECT 'chemo_ospatient_records',  COUNT(*) FROM chemo_ospatient_records  UNION ALL
SELECT 'immuno_ospatient_records', COUNT(*) FROM immuno_ospatient_records UNION ALL
SELECT 'autoimmune_inpatient_records',    COUNT(*) FROM autoimmune_inpatient_records    UNION ALL
SELECT 'autoimmune_inpatient_records_v2', COUNT(*) FROM autoimmune_inpatient_records_v2 UNION ALL
SELECT 'autoimmune_ospatient_records',    COUNT(*) FROM autoimmune_ospatient_records    UNION ALL
SELECT 'autoimmune_ospatient_records_v2', COUNT(*) FROM autoimmune_ospatient_records_v2;"

echo "=== DONE ==="
