#!/usr/bin/env bash
# run_pipeline.sh — execute the full lung-cancer gold-standard pipeline
# (Steps 1–5) against the synthetic cms_source + phewas MySQL DBs.
# Derived tables land in `lung_cancer_pipeline`.
#
# Scope: full cohort 2005-2018 (MAX + TAF). Covers the MAX-era 2005-2015
# branch, the TAF-2016 parallel branch, and the TAF-2017+ branch as ONE
# unified pipeline. The cohort lane extracts diagnosis records from all
# three eras (MAX / MAX1315 / TAF) and UNIONs them at step2. Treatment arms
# (chemo/immuno) and outcome (autoimmune) remain TAF-only by design —
# immunotherapy wasn't FDA-approved for lung cancer until March 2015, so
# pre-2016 exposure data is near-zero-signal. MAX patients diagnosed
# pre-2016 but treated post-2016 will still survive the INNER JOIN in
# step3 and contribute to the final survival tables.
#
# Prereqs:
#   1. cms_source loaded (see ../../synthetic_data/)
#   2. phewas loaded     (see ../../cohort_identification/load_phewas_mysql.sh)
#
# Expectation on current synthetic data: steps 1–5 run without errors.
# Chemo/immuno-arm tables downstream of step1 come up empty because
# cms_source.taf_other_services_line seeds LINE_PRCDR_CD with a single
# placeholder value (see ../../synthetic_data/KNOWN_GAPS.md § 1). The
# diagnosis-cohort + autoimmune-outcome arms populate normally.
#
# Usage:  bash run_pipeline.sh
#         DB_USER=foo DB_PASS=bar bash run_pipeline.sh

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
    { echo "SET SESSION sql_mode = '';"; sed 's/^[[:space:]]*--/--/' "$path"; } \
      | "${MYSQL[@]}" "$DB_NAME"
}

"${MYSQL[@]}" -e "
DROP DATABASE IF EXISTS $DB_NAME;
CREATE DATABASE $DB_NAME DEFAULT CHARACTER SET utf8mb4 DEFAULT COLLATE utf8mb4_unicode_ci;"

# --- Reference tables (derived from phewas + hardcoded HCPCS) ---------
run "reference/build_reference_tables"        reference/build_reference_tables.sql
run "reference/autoimmune_sub_slices"         reference/autoimmune_sub_slices.sql

# --- Step 1: extraction ----------------------------------------------
# Cohort lane: three era branches (MAX 2005-2012, MAX 2013-2015, TAF 2016+).
run "step1/lung_cohort_MAX     (2005-2012)"   step1_extraction/lung_cohort_MAX.sql
run "step1/lung_cohort_MAX1315 (2013-2015)"   step1_extraction/lung_cohort_MAX1315.sql
run "step1/lung_cohort_TAF     (2016+)"       step1_extraction/lung_cohort_TAF.sql
# Exposure + outcome: TAF only.
run "step1/exposure_chemo_immuno_TAF"         step1_extraction/exposure_chemo_immuno_TAF.sql
run "step1/outcome_autoimmune_TAF"            step1_extraction/outcome_autoimmune_TAF.sql

# --- Step 2: per-patient summary (_srt) ------------------------------
run "step2/srt_tables"                        step2_per_patient_summary/srt_tables.sql

# --- Step 3: merge cohort × exposure × outcome -----------------------
run "step3/cohort_x_exposure_x_outcome"       step3_merge/cohort_x_exposure_x_outcome.sql

# --- Step 4: inclusion rules + covariates ----------------------------
run "step4/prep_entire_records_and_covariates" step4_demographics_and_criteria/prep_entire_records_and_covariates.sql
run "step4/inclusion_and_covariates"          step4_demographics_and_criteria/inclusion_and_covariates.sql

# --- Step 5: final analytical tables ---------------------------------
run "step5/final_tables"                      step5_consolidate/final_tables.sql

echo
echo "=== Final row counts ==="
"${MYSQL[@]}" "$DB_NAME" -e "
SELECT 'ICD910_lung_cancer_codes',           COUNT(*) FROM ICD910_lung_cancer_codes           UNION ALL
SELECT 'chemo_cpt_codes',                    COUNT(*) FROM chemo_cpt_codes                    UNION ALL
SELECT 'immuno_cpt_codes',                   COUNT(*) FROM immuno_cpt_codes                   UNION ALL
SELECT 'autoimmune_icd',                     COUNT(*) FROM autoimmune_icd                     UNION ALL
SELECT '',                                   0                                                UNION ALL
SELECT 'lung_inpatient_records_MAX       (2005-2012)',  COUNT(*) FROM lung_inpatient_records_MAX        UNION ALL
SELECT 'lung_ospatient_records_MAX       (2005-2012)',  COUNT(*) FROM lung_ospatient_records_MAX        UNION ALL
SELECT 'lung_inpatient_records_MAX1315   (2013-2015)',  COUNT(*) FROM lung_inpatient_records_MAX1315    UNION ALL
SELECT 'lung_ospatient_records_MAX1315   (2013-2015)',  COUNT(*) FROM lung_ospatient_records_MAX1315    UNION ALL
SELECT 'lung_inpatient_records_orig      (TAF 2016+)',  COUNT(*) FROM lung_inpatient_records_orig       UNION ALL
SELECT 'lung_ospatient_records_orig      (TAF 2016+)',  COUNT(*) FROM lung_ospatient_records_orig       UNION ALL
SELECT 'chemo_ospatient_records',            COUNT(*) FROM chemo_ospatient_records            UNION ALL
SELECT 'immuno_ospatient_records',           COUNT(*) FROM immuno_ospatient_records           UNION ALL
SELECT 'autoimmune_inpatient_records_v2',    COUNT(*) FROM autoimmune_inpatient_records_v2    UNION ALL
SELECT 'autoimmune_ospatient_records_v2',    COUNT(*) FROM autoimmune_ospatient_records_v2    UNION ALL
SELECT '',                                   0                                                UNION ALL
SELECT 'lung_patient_srt',                   COUNT(*) FROM lung_patient_srt                   UNION ALL
SELECT 'chemo_ospatient_srt',                COUNT(*) FROM chemo_ospatient_srt                UNION ALL
SELECT 'immuno_ospatient_srt',               COUNT(*) FROM immuno_ospatient_srt               UNION ALL
SELECT 'autoimmune_patient_srt',             COUNT(*) FROM autoimmune_patient_srt             UNION ALL
SELECT '',                                   0                                                UNION ALL
SELECT 'lung_chemo_patients',                COUNT(*) FROM lung_chemo_patients                UNION ALL
SELECT 'lung_immuno_patients',               COUNT(*) FROM lung_immuno_patients               UNION ALL
SELECT 'lung_chemo_autoimmune_patient_info_v2',  COUNT(*) FROM lung_chemo_autoimmune_patient_info_v2  UNION ALL
SELECT 'lung_immuno_autoimmune_patient_info_v2', COUNT(*) FROM lung_immuno_autoimmune_patient_info_v2 UNION ALL
SELECT '',                                   0                                                UNION ALL
SELECT 'entire_records_inpatient',           COUNT(*) FROM entire_records_inpatient           UNION ALL
SELECT 'entire_records_ospatient',           COUNT(*) FROM entire_records_ospatient           UNION ALL
SELECT 'entire_records_before_diag_in',      COUNT(*) FROM entire_records_before_diag_in      UNION ALL
SELECT 'entire_records_before_diag_os',      COUNT(*) FROM entire_records_before_diag_os      UNION ALL
SELECT 'sickness',                           COUNT(*) FROM sickness                           UNION ALL
SELECT 'utilization',                        COUNT(*) FROM utilization                        UNION ALL
SELECT 'immuno_and_chemo_id',                COUNT(*) FROM immuno_and_chemo_id                UNION ALL
SELECT '',                                   0                                                UNION ALL
SELECT 'lung_chemo_autoimmune_patient_v4',   COUNT(*) FROM lung_chemo_autoimmune_patient_v4   UNION ALL
SELECT 'lung_immuno_autoimmune_patient_v4',  COUNT(*) FROM lung_immuno_autoimmune_patient_v4  UNION ALL
SELECT 'lung_chemo_autoimmune_patient_v7',   COUNT(*) FROM lung_chemo_autoimmune_patient_v7   UNION ALL
SELECT 'lung_immuno_autoimmune_patient_v7',  COUNT(*) FROM lung_immuno_autoimmune_patient_v7  UNION ALL
SELECT '',                                   0                                                UNION ALL
SELECT 'chemo_table_final (survival)',       COUNT(*) FROM chemo_table_final                  UNION ALL
SELECT 'immuno_table_final (survival)',      COUNT(*) FROM immuno_table_final                 UNION ALL
SELECT '',                                   0                                                UNION ALL
SELECT 'immuno_table_NO (Nivolumab)',        COUNT(*) FROM immuno_table_NO                    UNION ALL
SELECT 'immuno_table_PK (Pembrolizumab)',    COUNT(*) FROM immuno_table_PK                    UNION ALL
SELECT 'immuno_table_AT (Atezolizumab)',     COUNT(*) FROM immuno_table_AT                    UNION ALL
SELECT 'immuno_table_DI (Durvalumab)',       COUNT(*) FROM immuno_table_DI                    UNION ALL
SELECT 'immuno_table_IP (Ipilimumab)',       COUNT(*) FROM immuno_table_IP                    UNION ALL
SELECT 'immuno_table_AV (Avelumab)',         COUNT(*) FROM immuno_table_AV                    UNION ALL
SELECT '',                                   0                                                UNION ALL
SELECT 'immuno_table_dm / chemo_table_dm',           COUNT(*) FROM immuno_table_dm             UNION ALL
SELECT 'immuno_table_hypo / chemo_table_hypo',       COUNT(*) FROM immuno_table_hypo           UNION ALL
SELECT 'immuno_table_ra / chemo_table_ra',           COUNT(*) FROM immuno_table_ra             UNION ALL
SELECT 'immuno_table_thyro / chemo_table_thyro',     COUNT(*) FROM immuno_table_thyro;"

echo "=== DONE ==="
