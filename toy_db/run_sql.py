"""
MySQL SQL file runner — correctly handles DELIMITER $$ / stored procedures.

Used to load the diabetes pipeline's reference + Step-2 + Step-3 + Step-4
SQL into the small `cms_source` MySQL fixture seeded by `seed_mysql.py`.
The end state is everything the agent demo tests in `../tests/` need to
run.

Usage:
  python3 toy_db/seed_mysql.py    # populate cms_source first
  python3 toy_db/run_sql.py       # then this loads the reference + step SQL
"""

from __future__ import annotations

import os
import re
import sys

import mysql.connector

# Reuse the canonical splitter from agents/tools/sql_split.py so a single
# implementation drives both the agent's execute_sql tool and this runner.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from agents.tools.sql_split import split_by_delimiter, IGNORABLE  # noqa: E402

DB_CFG = dict(host='127.0.0.1', user='root', database='cms_source')

# Paths relative to the repo root. Each entry is (label, path).
SQL_FILES = [
    # Step 1 — reference tables
    ('Step 1a icd_9_cm',           'pipelines/diabetes/reference/icd_9_cm.sql'),
    ('Step 1b icd_code mapping',   'pipelines/diabetes/reference/icd_code.sql'),
    ('Step 1c hcpcs_codes',        'pipelines/diabetes/reference/hcpcs_code.sql'),
    # Step 2 — claims-lane extraction
    ('Step 2a inpatient 2005-12',  'pipelines/diabetes/step1_extraction/Re_all_inpatient.sql'),
    ('Step 2b inpatient 2013-15',  'pipelines/diabetes/step1_extraction/Re_all_inpatient1315.sql'),
    ('Step 2c outpatient 2005-12', 'pipelines/diabetes/step1_extraction/Re_all_other_therapy.sql'),
    ('Step 2d outpatient 2013-15', 'pipelines/diabetes/step1_extraction/Re_all_other_therapy1315.sql'),
    ('Step 2e TAF outpatient',     'pipelines/diabetes/step1_extraction/Re_All_other_services_header.sql'),
    ('Step 2f TAF inpatient',      'pipelines/diabetes/step1_extraction/Re_All_taf_inpatient.sql'),
    # Step 3 — combine
    ('Step 3  combine',            'pipelines/diabetes/step2_combine/all_combine.sql'),
    # Step 4 — SE-state filter
    ('Step 4  state filter',       'pipelines/diabetes/step3_filter/all_selected_state.sql'),
]


def run_file(label: str, path: str, con) -> list[str]:
    full_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        path,
    )
    if not os.path.exists(full_path):
        print(f"  {label}: SKIPPED (missing: {path})")
        return []

    with open(full_path, 'r') as fh:
        text = fh.read()

    stmts = split_by_delimiter(text)
    cur = con.cursor()
    errors: list[str] = []
    executed = 0

    for stmt, is_proc_block in stmts:
        if not stmt:
            continue
        code = re.sub(r'--[^\n]*', '', stmt)
        code = re.sub(r'/\*.*?\*/', '', code, flags=re.DOTALL).strip()
        if not code:
            continue
        try:
            cur.execute(stmt)
            try:
                while cur.nextset():
                    pass
            except Exception:
                pass
            executed += 1
        except mysql.connector.Error as e:
            if e.errno in IGNORABLE:
                continue
            errors.append(str(e)[:150])

    cur.close()
    con.commit()

    status = 'OK' if not errors else f'{len(errors)} error(s)'
    print(f"  {label}: {executed} stmts executed — {status}")
    for err in errors:
        print(f"    ✗ {err}")
    return errors


def verify(con) -> bool:
    cur = con.cursor()
    print("\n── Verification ─────────────────────────────────────────────────────")

    ext_tables = [
        'Re_all_inpatient', 'Re_all_inpatient1315',
        'Re_all_other_therapy', 'Re_all_other_therapy1315',
        'Re_All_other_services_header', 'Re_All_taf_inpatient_header',
    ]
    print("  Step 2 — extraction table row counts:")
    step2_ok = True
    for t in ext_tables:
        try:
            cur.execute(f"SELECT COUNT(*), COUNT(DISTINCT patient_id) FROM `{t}`")
            rows, pts = cur.fetchone()
            ok = rows > 0
            if not ok:
                step2_ok = False
            print(f"    [{'OK  ' if ok else 'EMPTY'}] {t}: {rows} rows, {pts} patients")
        except mysql.connector.Error as e:
            step2_ok = False
            print(f"    [MISS] {t}: {e}")

    try:
        cur.execute("SELECT COUNT(*), COUNT(DISTINCT patient_id) FROM all_combine")
        rows, pts = cur.fetchone()
        ok3 = rows > 0
        print(f"\n  Step 3 — all_combine: {rows} rows, {pts} patients  [{'OK' if ok3 else 'EMPTY'}]")
    except mysql.connector.Error as e:
        ok3 = False
        print(f"\n  Step 3 — ERROR: {e}")

    try:
        cur.execute("SELECT COUNT(*), COUNT(DISTINCT patient_id) FROM All_Selected_state")
        rows, pts = cur.fetchone()
        cur.execute("SELECT DISTINCT STATE_CD FROM All_Selected_state ORDER BY STATE_CD")
        states = [r[0] for r in cur.fetchall()]
        unexpected = set(states) - {'AL', 'FL', 'GA', 'MS', 'NC', 'SC', 'TN'}
        ok4 = len(unexpected) == 0 and rows > 0
        print(f"\n  Step 4 — All_Selected_state: {rows} rows, {pts} patients  [{'OK' if ok4 else 'FAIL'}]")
        print(f"           States: {states}")
        if unexpected:
            print(f"           Unexpected states: {unexpected}")
    except mysql.connector.Error as e:
        ok4 = False
        print(f"\n  Step 4 — ERROR: {e}")

    cur.close()
    return step2_ok and ok3 and ok4


def main() -> None:
    con = mysql.connector.connect(**DB_CFG)
    print("Loading diabetes pipeline reference + Step-2/3/4 SQL into cms_source\n")

    all_errors: list[str] = []
    for label, path in SQL_FILES:
        errs = run_file(label, path, con)
        all_errors.extend(errs)

    passed = verify(con)
    if passed and not all_errors:
        print("\nALL STEPS PASSED ✓")
    else:
        print("\nISSUES FOUND — see above ✗")
    con.close()


if __name__ == '__main__':
    main()
