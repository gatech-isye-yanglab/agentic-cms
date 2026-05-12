#!/usr/bin/env bash
# Download CMS synthetic claims data. These datasets are multi-GB and
# publicly redistributable — we keep them OUT of git/LFS and fetch on
# demand here.
#
# Datasets:
#   1. CMS Synthetic RIF 2023 (Medicare; Synthea-generated; 8,671 bene)
#   2. CMS DE-SynPUF 2008–2010 Sample 1 (Medicare; 5% sample; ~1.2 GB)
#
# Usage (script lives at synthetic_data/download_synthetic_data.sh):
#   bash synthetic_data/download_synthetic_data.sh          # both
#   bash synthetic_data/download_synthetic_data.sh rif      # RIF 2023
#   bash synthetic_data/download_synthetic_data.sh synpuf   # DE-SynPUF
#
# Target paths (matches .gitignore):
#   synthetic_data/synthetic_rif_2023/
#   synthetic_data/de_synpuf_2008_2010/

set -euo pipefail

# Resolve back to repo root regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}/.."
REPO_ROOT="$(pwd)"

WHICH="${1:-all}"

# ─── URLs (update here if CMS moves them) ───────────────────────────
# CMS Synthetic RIF 2023:
#   https://data.cms.gov/collection/synthetic-medicare-enrollment-fee-for-service-claims-and-prescription-drug-events
# DE-SynPUF 2008–2010:
#   https://www.cms.gov/data-research/statistics-trends-and-reports/medicare-claims-synthetic-public-use-files/cms-2008-2010-data-entrepreneurs-synthetic-public-use-file-de-synpuf
#
# NOTE: CMS occasionally re-hosts these. If a URL 404s, go to the
# landing page above and grab the current download link.

RIF_BASE_URL="https://data.cms.gov/sites/default/files/2024-03/"  # verify
SYNPUF_BASE_URL="https://www.cms.gov/files/zip/de10-sample-1.zip"  # 10 pieces per sample

# ─── Helpers ────────────────────────────────────────────────────────
have_tool() { command -v "$1" >/dev/null 2>&1; }

download_to() {
  local url="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]]; then
    echo "  (already have $dest — skipping)"
    return 0
  fi
  echo "  fetching $url"
  if have_tool curl; then
    curl -L --fail -o "$dest" "$url"
  elif have_tool wget; then
    wget -O "$dest" "$url"
  else
    echo "ERROR: need curl or wget" >&2; return 1
  fi
}

# ─── DE-SynPUF 2008–2010 (Sample 1) ─────────────────────────────────
download_synpuf() {
  cat <<'EOF'
=== DE-SynPUF 2008–2010 Sample 1 (~1.2 GB) ===

CMS distributes these from a landing page that hand-rolls the
download links per visit, so this script can't curl the files
directly. Manual steps:

  1. Open the CMS landing page:
       https://www.cms.gov/data-research/statistics-trends-and-reports/medicare-claims-synthetic-public-use-files/cms-2008-2010-data-entrepreneurs-synthetic-public-use-file-de-synpuf

  2. Under "Sample 1", download these 8 ZIP files into
     synthetic_data/de_synpuf_2008_2010/ :

       DE1_0_2008_Beneficiary_Summary_File_Sample_1.zip
       DE1_0_2009_Beneficiary_Summary_File_Sample_1.zip
       DE1_0_2010_Beneficiary_Summary_File_Sample_1.zip
       DE1_0_2008_to_2010_Carrier_Claims_Sample_1A.zip
       DE1_0_2008_to_2010_Carrier_Claims_Sample_1B.zip
       DE1_0_2008_to_2010_Inpatient_Claims_Sample_1.zip
       DE1_0_2008_to_2010_Outpatient_Claims_Sample_1.zip
       DE1_0_2008_to_2010_Prescription_Drug_Events_Sample_1.zip

  3. Unzip each into the same directory. The build only strictly
     needs DE1_0_2008_Beneficiary_Summary_File_Sample_1.csv (used as
     a BENE_ID bootstrap pool); the other claim files are unused
     downstream but listed here for completeness.

  4. Re-run synthetic_data/build_cms_source.sh.

License: public domain (CMS).
EOF
}

# ─── CMS Synthetic RIF 2023 ─────────────────────────────────────────
download_rif() {
  cat <<'EOF'
=== CMS Synthetic RIF 2023 (8,671 beneficiaries; ~1 GB) ===

Same story — landing-page-only distribution, manual steps:

  1. Open the CMS collection page:
       https://data.cms.gov/collection/synthetic-medicare-enrollment-fee-for-service-claims-and-prescription-drug-events

  2. From the "Synthetic Medicare Beneficiary, Enrollment, FFS Claims
     and PDE 2023" dataset, download the per-table CSVs into
     synthetic_data/synthetic_rif_2023/ :

       beneficiary_2015.csv … beneficiary_2023.csv  (one per year)
       inpatient.csv
       outpatient.csv
       carrier.csv
       pde.csv

     (load_rif.py reads beneficiary, inpatient, outpatient, and pde;
     the others are not strictly required.)

  3. Re-run synthetic_data/build_cms_source.sh.

License: public domain (CMS / Synthea).
EOF
}

# ─── Main ───────────────────────────────────────────────────────────
case "$WHICH" in
  rif)    download_rif ;;
  synpuf) download_synpuf ;;
  all)    download_synpuf; download_rif ;;
  *)      echo "Usage: $0 [rif|synpuf|all]"; exit 2 ;;
esac

echo ""
echo "✓ Done. Files under synthetic_data/ are gitignored — do not"
echo "  git add them. This keeps the repo small and avoids burning LFS"
echo "  bandwidth on re-downloadable public data."
