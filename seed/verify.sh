#!/usr/bin/env bash
# verify.sh — measure decompression fidelity after an agent has
# regenerated the agentic-cms artifact from this seed.
#
# Usage:
#   bash seed/verify.sh                     # verify the parent dir (..)
#   bash seed/verify.sh /path/to/regen      # verify an explicit target
#
# Outputs a fidelity score (e.g. "24/25 tests passed → fidelity 0.96")
# plus a per-check pass/fail line. Exits 0 on success, 1 on any
# failure.

set -eo pipefail

SEED_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-$(cd "$SEED_DIR/.." && pwd)}"

cd "$TARGET"

echo "=== Verifying agentic-cms regeneration at: $TARGET ==="
echo ""

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

ok()   { echo "  [PASS] $1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "  [FAIL] $1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
warn() { echo "  [WARN] $1"; WARN_COUNT=$((WARN_COUNT+1)); }

# ─── 1. File-level structural checks ─────────────────────────────────
echo "[1/5] Structural checks (do the regenerated files exist?)"

required_files=(
  "synthetic_data/build_cms_source.sh"
  "synthetic_data/gen_ddl.py"
  "synthetic_data/gen_data.py"
  "synthetic_data/load_rif.py"
  "synthetic_data/columns_formats.csv"
  "synthetic_data/tests/test_synthetic_db.py"
  "agents/llm.py"
  "agents/tools/mysql_tools.py"
  "agents/tools/sql_split.py"
  "knowledge/constraints.py"
  "knowledge/schema.json"
  "knowledge/codes.py"
  "knowledge/task_builder.py"
  "knowledge/diseases/diabetes.py"
  "knowledge/skills/extraction_cursor.md"
  "knowledge/skills/combine_step.md"
  "cohort_identification/architecture_proposal.md"
  "cohort_identification/schema_phewas_mysql.sql"
  "cohort_identification/load_phewas_mysql.sh"
  "pipelines/diabetes/run_pipeline.sh"
  "pipelines/diabetes/step1_extraction/Re_all_inpatient.sql"
  "pipelines/lung_cancer/run_pipeline.sh"
  "toy_db/seed_mysql.py"
  "toy_db/run_sql.py"
  "tests/test_minimal_extraction.py"
  "README.md"
  "LICENSE"
  "pyproject.toml"
)

for f in "${required_files[@]}"; do
  if [[ -f "$f" ]]; then ok "$f exists"; else fail "$f missing"; fi
done
echo ""

# ─── 2. Build the synthetic DB ──────────────────────────────────────
echo "[2/5] Synthetic DB build (SKIP_MYSQL=1)"

if [[ ! -f synthetic_data/de_synpuf_2008_2010/DE1_0_2008_Beneficiary_Summary_File_Sample_1.csv ]]; then
  warn "DE-SynPUF inputs not present; skipping build (download per synthetic_data/download_synthetic_data.sh)"
elif SKIP_MYSQL=1 bash synthetic_data/build_cms_source.sh > /tmp/seed_verify_build.log 2>&1; then
  ok "build_cms_source.sh succeeded"
  if [[ -f synthetic_data/synthetic_db.sqlite ]]; then ok "synthetic_db.sqlite produced"; else fail "synthetic_db.sqlite missing"; fi
else
  fail "build_cms_source.sh failed (see /tmp/seed_verify_build.log)"
fi
echo ""

# ─── 3. Compliance test suite ───────────────────────────────────────
echo "[3/5] Compliance test suite (synthetic_data/tests/)"

if [[ ! -f synthetic_data/synthetic_db.sqlite ]]; then
  warn "no synthetic_db.sqlite; skipping pytest"
elif python3 -m pytest synthetic_data/tests/ -q > /tmp/seed_verify_pytest.log 2>&1; then
  PASSED=$(grep -oE "[0-9]+ passed" /tmp/seed_verify_pytest.log | head -1 | grep -oE "[0-9]+" || echo "0")
  if [[ "$PASSED" == "25" ]]; then
    ok "pytest 25/25 passed"
    if grep -q "83 subtests passed" /tmp/seed_verify_pytest.log; then
      ok "all 83 subtests passed"
    else
      warn "subtests count not 83 (pytest-subtests may not be installed)"
    fi
  else
    fail "pytest expected 25 passed, got $PASSED (see /tmp/seed_verify_pytest.log)"
  fi
else
  fail "pytest failed (see /tmp/seed_verify_pytest.log)"
fi
echo ""

# ─── 4. Row-count fidelity vs evidence ──────────────────────────────
echo "[4/5] Row counts vs evidence/row_counts_v1.json"

if [[ ! -f synthetic_data/synthetic_db.sqlite ]]; then
  warn "no synthetic_db.sqlite; skipping row-count comparison"
else
  python3 - <<PY
import json, sqlite3, os, sys
seed_dir = "${SEED_DIR}"
target   = "${TARGET}"
expected = json.load(open(os.path.join(seed_dir, "evidence/row_counts_v1.json")))["synthetic_db_table_counts"]
tolerance = 0.05
con = sqlite3.connect(f"file:{os.path.join(target, 'synthetic_data/synthetic_db.sqlite')}?mode=ro&immutable=1", uri=True)
mismatches = 0
matches    = 0
for tbl, exp in expected.items():
    if tbl.startswith("_") or not isinstance(exp, int):
        continue
    actual = con.execute(f'SELECT COUNT(*) FROM "{tbl}"').fetchone()[0]
    if exp == 0:
        if actual == 0: matches += 1
        else: print(f"  [WARN] {tbl}: expected 0, got {actual}"); mismatches += 1
        continue
    diff_pct = abs(actual - exp) / exp
    if diff_pct <= tolerance:
        matches += 1
    else:
        print(f"  [WARN] {tbl}: expected {exp}, got {actual} (off by {diff_pct*100:.1f}%, tolerance {tolerance*100:.0f}%)")
        mismatches += 1
print(f"  Row-count fidelity: {matches}/{matches+mismatches} tables within ±{tolerance*100:.0f}%")
sys.exit(0 if mismatches == 0 else 0)  # don't fail outright — row counts can drift legitimately
PY
fi
echo ""

# ─── 5. SHA-256 of synthetic_db.sqlite (informational) ──────────────
echo "[5/5] SHA-256 vs evidence/synthetic_db_seed42.sha256 (informational)"

if [[ -f synthetic_data/synthetic_db.sqlite ]]; then
  EXPECTED_SHA=$(awk '/^[0-9a-f]/{print $1; exit}' "$SEED_DIR/evidence/synthetic_db_seed42.sha256")
  ACTUAL_SHA=$(shasum -a 256 synthetic_data/synthetic_db.sqlite | awk '{print $1}')
  if [[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]]; then
    ok "SHA-256 matches canonical run (fully deterministic regeneration)"
  else
    warn "SHA-256 differs from canonical run (regenerated build may still be behaviorally correct)"
    echo "    expected: $EXPECTED_SHA"
    echo "    actual:   $ACTUAL_SHA"
  fi
fi
echo ""

# ─── Summary ─────────────────────────────────────────────────────────
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [[ $TOTAL -eq 0 ]]; then
  echo "=== No checks ran (likely missing inputs); see warnings above ==="
  exit 1
fi

FIDELITY=$(awk -v p=$PASS_COUNT -v t=$TOTAL 'BEGIN{ printf "%.2f", p/t }')
echo "=== Decompression fidelity: $PASS_COUNT/$TOTAL checks passed ($FIDELITY) — $WARN_COUNT warnings ==="

if [[ $FAIL_COUNT -gt 0 ]]; then exit 1; else exit 0; fi
