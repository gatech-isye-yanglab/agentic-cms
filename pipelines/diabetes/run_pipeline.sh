#!/usr/bin/env bash
# run_pipeline.sh — execute the diabetes gold-standard pipeline end-to-end
# against the `cms_source` synthetic DB. Derived tables land in
# `diabetes_pipeline`. Requires MySQL reachable at 127.0.0.1:3306.
#
# Usage:   bash run_pipeline.sh        (defaults: root / empty password)
#          DB_USER=foo DB_PASS=bar bash run_pipeline.sh
#
# The sed pipe normalises leading-whitespace comment lines (" --") so the
# mysql client correctly recognises DELIMITER as a client-side directive.

set -e
DB_USER=${DB_USER:-root}
DB_HOST=${DB_HOST:-127.0.0.1}
DB_NAME=${DB_NAME:-diabetes_pipeline}

MYSQL_PWD_OPT=()
if [[ -n "${DB_PASS:-}" ]]; then
    MYSQL_PWD_OPT=(-p"$DB_PASS")
fi

run() {
    local label="$1"
    local path="$2"
    echo "=== $label ==="
    # sql_mode='' relaxes the NO_ZERO_DATE/STRICT_TRANS_TABLES checks so
    # sentinel '0000-00-00' dates in taf_demog_elig_base flow through.
    { echo "SET SESSION sql_mode = '';"; sed 's/^[[:space:]]*--/--/' "$path"; } \
      | mysql -u "$DB_USER" -h "$DB_HOST" "${MYSQL_PWD_OPT[@]}" "$DB_NAME"
}

cd "$(dirname "$0")"

# Reset the working DB so reruns are idempotent.
mysql -u "$DB_USER" -h "$DB_HOST" "${MYSQL_PWD_OPT[@]}" \
    -e "DROP DATABASE IF EXISTS $DB_NAME; CREATE DATABASE $DB_NAME DEFAULT CHARACTER SET utf8mb4 DEFAULT COLLATE utf8mb4_unicode_ci;"

# Reference tables (only icd_9_cm is actually referenced by step1).
run "ref/icd_9_cm"         reference/icd_9_cm.sql
run "ref/icd_code"         reference/icd_code.sql
run "ref/hcpcs_code"       reference/hcpcs_code.sql

# Step 1 — claims lane (6 tables).
run "Re_all_inpatient"              step1_extraction/Re_all_inpatient.sql
run "Re_all_inpatient1315"          step1_extraction/Re_all_inpatient1315.sql
run "Re_all_other_therapy"          step1_extraction/Re_all_other_therapy.sql
run "Re_all_other_therapy1315"      step1_extraction/Re_all_other_therapy1315.sql
run "Re_All_other_services_header"  step1_extraction/Re_All_other_services_header.sql
run "Re_All_taf_inpatient_header"   step1_extraction/Re_All_taf_inpatient.sql

# Step 1 — demographics lane (3 tables).
run "Re_personal_summary"      step1_extraction/Re_personal_summary.sql
run "Re_personal_summary1315"  step1_extraction/Re_personal_summary1315.sql
run "Re_taf_demog_elig_base"   step1_extraction/Re_taf_demog_elig_base.sql

# Step 2 — combine per lane.
run "all_combine"       step2_combine/all_combine.sql
run "all_combine_demo"  step2_combine/all_combine_demo.sql

# Step 3 — SE-state filter per lane.
run "All_Selected_state"       step3_filter/all_selected_state.sql
run "All_Selected_state_demo"  step3_filter/all_selected_state_demo.sql

# Step 4 — 24-month incident flag (GA only).
run "temp_all_in_two_years_GA" step4_two_year/all_in_two_years.sql

# Step 5 — consolidate + ambiguity resolution.
run "patient_flag_summary_GA / single_row_patient_temp" step5_consolidate/step_2.sql
run "attach demographics"                               step5_consolidate/step_3.sql

echo "=== DONE ==="
