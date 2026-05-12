#!/usr/bin/env bash
# build_cms_source.sh — rebuild the synthetic `cms_source` database end-to-end
# in Tier 2a mode: RIF for TAF-era tables + gen_data.py for MAX-era + meta.
#
# Order:
#   1. gen_ddl.py emits schema_mysql.sql + schema_sqlite.sql from
#      columns_formats.csv.
#   2. gen_data.py produces all 21 tables as CSVs (MAX + TAF + meta).
#   3. load_rif.py OVERWRITES the 7 TAF CSVs with Synthea-sourced RIF data
#      + a Python HCPCS overlay for the lung-cancer oncology cohort.
#   4. load_mysql.sql loads the final CSV set into MySQL cms_source
#      (skipped when SKIP_MYSQL=1).
#   5. pytest tests/ — all structural tests must pass.
#
# Usage:  bash build_cms_source.sh
#         SKIP_MYSQL=1 bash build_cms_source.sh           # SQLite + tests only
#         DB_USER=foo DB_PASS=bar bash build_cms_source.sh

set -eo pipefail

DB_USER=${DB_USER:-root}
DB_HOST=${DB_HOST:-127.0.0.1}
DB_PASS=${DB_PASS:-}
SKIP_MYSQL=${SKIP_MYSQL:-0}

MYSQL=(mysql -u "$DB_USER" -h "$DB_HOST" --local-infile=1)
if [[ -n "$DB_PASS" ]]; then
    MYSQL+=("-p$DB_PASS")
fi

cd "$(dirname "$0")"

# Preflight — both Tier 1 and Tier 2a need their public input datasets in
# place. Neither is committed to this repo (they total ~4 GB and are
# publicly redownloadable from CMS).
SYNPUF_BENE="de_synpuf_2008_2010/DE1_0_2008_Beneficiary_Summary_File_Sample_1.csv"
RIF_DIR="synthetic_rif_2023"
missing=0
if [[ ! -f "$SYNPUF_BENE" ]]; then
    echo "ERROR: missing DE-SynPUF beneficiary file: synthetic_data/$SYNPUF_BENE" >&2
    missing=1
fi
if [[ ! -d "$RIF_DIR" ]] || [[ -z "$(ls -A "$RIF_DIR" 2>/dev/null)" ]]; then
    echo "ERROR: missing CMS Synthetic RIF 2023 data: synthetic_data/$RIF_DIR/" >&2
    missing=1
fi
if [[ "$missing" == "1" ]]; then
    cat >&2 <<MSG

Both inputs are public CMS datasets (~4 GB total) and not committed to
this repo. Download them per the URLs in:

    synthetic_data/download_synthetic_data.sh
    docs/synthetic_data.md

Expected layout:

    synthetic_data/de_synpuf_2008_2010/DE1_0_2008_Beneficiary_Summary_File_Sample_1.csv
    synthetic_data/synthetic_rif_2023/{beneficiary_YYYY,inpatient,outpatient,pde}.csv

Once they're in place, re-run this script.
MSG
    exit 2
fi

echo "=== 1. gen_ddl.py (emit schema_mysql.sql + schema_sqlite.sql) ==="
python3 gen_ddl.py

echo
echo "=== 2. gen_data.py (Python-generated MAX-era + initial TAF stubs) ==="
rm -f synthetic_db.sqlite synthetic_db.sqlite-journal
python3 gen_data.py --sqlite synthetic_db.sqlite --csv ./csv --n-patients all

echo
echo "=== 3. load_rif.py (overwrite TAF CSVs with Synthea RIF + oncology overlay) ==="
python3 load_rif.py --csv ./csv

if [[ "$SKIP_MYSQL" != "1" ]]; then
    echo
    echo "=== 4. Reload MySQL cms_source ==="
    "${MYSQL[@]}" -e "SET GLOBAL local_infile = 1;" >/dev/null
    "${MYSQL[@]}" < schema_mysql.sql
    "${MYSQL[@]}" cms_source < load_mysql.sql | tail -30
else
    echo
    echo "=== 4. MySQL load (skipped: SKIP_MYSQL=1) ==="
fi

echo
echo "=== 5. pytest ==="
python3 -m pytest tests/ -q

echo
echo "=== DONE — cms_source rebuilt in Tier 2a mode ==="
