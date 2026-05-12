#!/usr/bin/env bash
# load_phewas_mysql.sh — build the MySQL `phewas` DB from the committed
# PhecodeX v1.0 CSVs in databases/phewas/.
#
# Usage:   bash load_phewas_mysql.sh
#          DB_USER=foo DB_PASS=bar bash load_phewas_mysql.sh
#
# Requires the server flag --local-infile=1 (LOAD DATA LOCAL INFILE). If
# it's OFF we flip it on via `SET GLOBAL local_infile=1` once.
#
# The CSVs stay as the canonical source of truth; this script produces
# the joinable MySQL copy. Rerun whenever the CSVs change.

set -eo pipefail

DB_USER=${DB_USER:-root}
DB_HOST=${DB_HOST:-127.0.0.1}
DB_PASS=${DB_PASS:-}

MYSQL=(mysql -u "$DB_USER" -h "$DB_HOST" --local-infile=1)
if [[ -n "$DB_PASS" ]]; then
    MYSQL+=("-p$DB_PASS")
fi

cd "$(dirname "$0")"
CSV_DIR="$(pwd)/databases/phewas"

if [[ ! -f "$CSV_DIR/phecodeX_info.csv" ]]; then
    echo "ERROR: $CSV_DIR/phecodeX_info.csv not found. Did the CSVs get unpacked from phecodeX_vocabulary.zip?" >&2
    exit 1
fi

# Enable LOAD DATA LOCAL INFILE on the server side if the admin hasn't.
"${MYSQL[@]}" -e "SET GLOBAL local_infile = 1;" >/dev/null

# Apply schema (drops + recreates everything).
"${MYSQL[@]}" < schema_phewas_mysql.sql

# Helper for LOAD DATA with standard CSV dialect.
load_csv () {
    local table="$1"
    local file="$2"
    local cols="$3"   # comma-separated column list, in file order
    echo "  loading $table from ${file##*/} ..."
    "${MYSQL[@]}" phewas <<SQL
LOAD DATA LOCAL INFILE '$file'
INTO TABLE \`$table\`
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
($cols);
SQL
}

echo "Loading CSVs ..."
load_csv phecodeX_info              "$CSV_DIR/phecodeX_info.csv" \
         "phecode,phecode_string,category_num,category,sex,icd10_only,phecode_num"
load_csv phecodeX_ICD_CM_map_flat   "$CSV_DIR/phecodeX_ICD_CM_map_flat.csv" \
         "ICD,vocabulary_id,ICD_string,phecode,phecode_string,category_num,category"
load_csv phecodeX_unrolled_ICD_CM   "$CSV_DIR/phecodeX_unrolled_ICD_CM.csv" \
         "phecode,ICD,vocabulary_id"
load_csv phecodeX_ICD_WHO_map_flat  "$CSV_DIR/phecodeX_ICD_WHO_map_flat.csv" \
         "icd,vocabulary_id,ICD_string,phecode,phecode_string,category_num,category"
load_csv phecodeX_unrolled_ICD_WHO  "$CSV_DIR/phecodeX_unrolled_ICD_WHO.csv" \
         "phecode,ICD,vocabulary_id"

echo
echo "Row counts:"
"${MYSQL[@]}" phewas -e "
SELECT 'phecodeX_info',              COUNT(*) FROM phecodeX_info              UNION ALL
SELECT 'phecodeX_ICD_CM_map_flat',   COUNT(*) FROM phecodeX_ICD_CM_map_flat   UNION ALL
SELECT 'phecodeX_unrolled_ICD_CM',   COUNT(*) FROM phecodeX_unrolled_ICD_CM   UNION ALL
SELECT 'phecodeX_ICD_WHO_map_flat',  COUNT(*) FROM phecodeX_ICD_WHO_map_flat  UNION ALL
SELECT 'phecodeX_unrolled_ICD_WHO',  COUNT(*) FROM phecodeX_unrolled_ICD_WHO;"

echo
echo "Smoke test — lung-cancer phecode (PhecodeX) expansion:"
"${MYSQL[@]}" phewas -e "
SELECT i.phecode, i.phecode_num, i.phecode_string,
       COUNT(*) AS n_icd_children
FROM phecodeX_info i
JOIN phecodeX_unrolled_ICD_CM u ON u.phecode = i.phecode
WHERE i.phecode_string LIKE '%bronchus%lung%' OR i.phecode_string LIKE '%lung%bronchus%'
GROUP BY i.phecode, i.phecode_num, i.phecode_string;"

echo "DONE."
