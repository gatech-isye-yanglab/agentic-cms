"""
test_synthetic_db.py — Integration tests for the schema-exact synthetic DB.

Runs against the SQLite build produced by gen_data.py.  Exercises four
categories:

    (1) schema integrity — all 21 tables exist, column names and declared
        types match `columns_formats.csv` exactly.
    (2) referential integrity — BENE_ID / PATIENT_ID are consistent across
        tables that reference the same beneficiary.
    (3) partition-filter presence — state_key + year columns are populated
        and can be filtered independently.
    (4) diabetes-pipeline smoke — Step 1 / Step 2 from the gold-standard
        pipeline can be expressed against this schema and produce > 0 rows
        per era table.

Usage:
    pytest -q tests/test_synthetic_db.py
or
    python3 tests/test_synthetic_db.py
"""

from __future__ import annotations

import csv
import os
import sqlite3
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)  # synthetic_data/
DB   = os.path.join(ROOT, "synthetic_db.sqlite")
CSV  = os.path.join(ROOT, "columns_formats.csv")

EXPECTED_TABLES = [
    "data_years", "inpatient", "inpatient1315", "messagelog",
    "other_therapy", "other_therapy1315",
    "personal_summary", "personal_summary1315",
    "rx", "rx1315", "state_codes",
    "table_counts", "table_counts_by_state", "table_osline_counts_by_state",
    "taf_demog_elig_base", "taf_inpatient_header", "taf_inpatient_line",
    "taf_other_services_header", "taf_other_services_line",
    "taf_rx_header", "taf_rx_line",
]

SE_STATES = {"AL", "FL", "GA", "MS", "NC", "SC", "TN"}


def open_db(path: str) -> sqlite3.Connection:
    """Open the synthetic DB read-only.

    Some containerized FUSE/virtiofs mounts do not support SQLite's POSIX
    file locking — opening the DB in default mode crashes with a disk-I/O
    error or silently truncates the file. Using `?mode=ro&immutable=1`
    skips locking entirely. Users running the tests against a local MySQL
    should swap out this helper.
    """
    return sqlite3.connect(f"file:{path}?mode=ro&immutable=1", uri=True)


def load_expected_columns():
    """Map {table_name: [(col_name, mysql_type), ...]} from the schema CSV."""
    out: dict[str, list[tuple[str, str]]] = {}
    with open(CSV) as f:
        r = csv.DictReader(f)
        for row in r:
            out.setdefault(row["table_name"], []).append(
                (int(row["column_order"]), row["column_name"], row["full_type"])
            )
    return {t: [(c, tp) for _, c, tp in sorted(cols)] for t, cols in out.items()}


# Translate MySQL type to the SQLite affinity string `PRAGMA table_info`
# returns.  This must match the mapping in gen_ddl.py.
def mysql_to_sqlite_affinity(full_type: str) -> str:
    t = full_type.strip().lower()
    if t in ("date", "timestamp") or t.startswith("varchar"):
        return "TEXT"
    if t.startswith("decimal"):
        return "REAL"
    if t.startswith(("int", "bigint", "tinyint")):
        return "INTEGER"
    raise AssertionError(f"unknown type: {full_type!r}")


class SchemaIntegrity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.conn = open_db(DB)
        cls.conn.row_factory = sqlite3.Row  # for name-based row access
        cls.expected = load_expected_columns()

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def test_all_21_tables_present(self):
        rows = self.conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        ).fetchall()
        actual = sorted(r[0] for r in rows)
        self.assertEqual(actual, sorted(EXPECTED_TABLES),
                         "Tables don't match the expected institutional inventory")

    def test_column_names_and_order_match_csv(self):
        for tbl, expected in self.expected.items():
            with self.subTest(table=tbl):
                got = self.conn.execute(f'PRAGMA table_info("{tbl}")').fetchall()
                got_names = [r["name"] for r in got]
                exp_names = [c for c, _ in expected]
                self.assertEqual(
                    got_names, exp_names,
                    f"{tbl}: column name/order mismatch",
                )

    def test_column_types_match_affinity(self):
        for tbl, expected in self.expected.items():
            with self.subTest(table=tbl):
                got = self.conn.execute(f'PRAGMA table_info("{tbl}")').fetchall()
                for (cname, mysql_type), row in zip(expected, got):
                    aff = mysql_to_sqlite_affinity(mysql_type)
                    self.assertEqual(
                        row["type"], aff,
                        f"{tbl}.{cname} expected {aff} got {row['type']}",
                    )

    def test_total_column_count(self):
        total = 0
        for tbl in EXPECTED_TABLES:
            n = len(self.conn.execute(f'PRAGMA table_info("{tbl}")').fetchall())
            total += n
        self.assertEqual(total, 2533, "Total column count across 21 tables")


class ReferentialIntegrity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.conn = open_db(DB)

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def test_bene_ids_consistent_between_claim_and_demographics_era1(self):
        """Every BENE_ID in `inpatient` should also appear in `personal_summary`."""
        bad = self.conn.execute("""
            SELECT COUNT(DISTINCT ip.BENE_ID)
            FROM inpatient ip
            LEFT JOIN personal_summary ps USING (BENE_ID)
            WHERE ps.BENE_ID IS NULL
        """).fetchone()[0]
        self.assertEqual(bad, 0, "inpatient rows without personal_summary")

    def test_bene_ids_consistent_between_claim_and_demographics_era2(self):
        bad = self.conn.execute("""
            SELECT COUNT(DISTINCT ip.BENE_ID)
            FROM inpatient1315 ip
            LEFT JOIN personal_summary1315 ps USING (BENE_ID)
            WHERE ps.BENE_ID IS NULL
        """).fetchone()[0]
        self.assertEqual(bad, 0)

    def test_bene_ids_consistent_between_claim_and_demographics_era3(self):
        bad = self.conn.execute("""
            SELECT COUNT(DISTINCT ih.BENE_ID)
            FROM taf_inpatient_header ih
            LEFT JOIN taf_demog_elig_base d USING (BENE_ID)
            WHERE d.BENE_ID IS NULL
        """).fetchone()[0]
        self.assertEqual(bad, 0)

    def test_header_line_clm_id_linkage(self):
        """Every line row's CLM_ID must exist in the matching header table."""
        for header, line in [
            ("taf_inpatient_header",      "taf_inpatient_line"),
            ("taf_other_services_header", "taf_other_services_line"),
            ("taf_rx_header",             "taf_rx_line"),
        ]:
            with self.subTest(header=header, line=line):
                orphans = self.conn.execute(f"""
                    SELECT COUNT(*)
                    FROM {line} l
                    LEFT JOIN {header} h USING (CLM_ID)
                    WHERE h.CLM_ID IS NULL
                """).fetchone()[0]
                self.assertEqual(orphans, 0, f"{line} has orphan CLM_IDs")

    def test_state_codes_lookup_covers_claim_states(self):
        """Every STATE_CD observed on a claim must exist in `state_codes`."""
        known = {r[0] for r in self.conn.execute("SELECT state_code FROM state_codes")}
        for tbl in ["inpatient", "inpatient1315", "taf_inpatient_header"]:
            with self.subTest(table=tbl):
                seen = {r[0] for r in self.conn.execute(
                    f'SELECT DISTINCT STATE_CD FROM {tbl} WHERE STATE_CD IS NOT NULL')}
                missing = seen - known
                self.assertFalse(missing, f"{tbl}: unknown STATE_CD {missing}")


class PartitionFilters(unittest.TestCase):
    """The institutional partition rule requires queries to include
    state_key + year filters. These tests prove the columns are populated
    and work as partition keys."""

    @classmethod
    def setUpClass(cls):
        cls.conn = open_db(DB)

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def test_state_key_populated(self):
        # Every era-1/era-2 claim row must have a non-null state_key.
        for tbl in ["inpatient", "inpatient1315", "other_therapy",
                    "other_therapy1315", "rx", "rx1315"]:
            with self.subTest(table=tbl):
                n = self.conn.execute(
                    f'SELECT COUNT(*) FROM {tbl} WHERE state_key IS NULL'
                ).fetchone()[0]
                self.assertEqual(n, 0, f"{tbl} has NULL state_key")

    def test_STATE_KEY_populated_in_taf(self):
        for tbl in ["taf_inpatient_header", "taf_inpatient_line",
                    "taf_other_services_header", "taf_other_services_line",
                    "taf_rx_header", "taf_rx_line", "taf_demog_elig_base"]:
            with self.subTest(table=tbl):
                n = self.conn.execute(
                    f'SELECT COUNT(*) FROM {tbl} WHERE STATE_KEY IS NULL'
                ).fetchone()[0]
                self.assertEqual(n, 0, f"{tbl} has NULL STATE_KEY")

    def test_year_columns_populated(self):
        pairs = [
            ("inpatient",         "YR_NUM"),
            ("inpatient1315",     "YR_NUM"),
            ("other_therapy",     "YR_NUM"),
            ("other_therapy1315", "YR_NUM"),
            ("rx",                "YR_NUM"),
            ("rx1315",            "YR_NUM"),
            ("taf_inpatient_header",      "RFRNC_YR"),
            ("taf_other_services_header", "RFRNC_YR"),
            ("taf_rx_header",             "RFRNC_YR"),
        ]
        for tbl, col in pairs:
            with self.subTest(table=tbl, col=col):
                n = self.conn.execute(
                    f'SELECT COUNT(*) FROM {tbl} WHERE {col} IS NULL'
                ).fetchone()[0]
                self.assertEqual(n, 0, f"{tbl}.{col} has NULLs")

    def test_partition_filter_reduces_rows(self):
        """A partition filter should always return ≤ the unfiltered count."""
        tbl = "inpatient"
        total = self.conn.execute(f'SELECT COUNT(*) FROM {tbl}').fetchone()[0]
        filtered = self.conn.execute(
            f'SELECT COUNT(*) FROM {tbl} WHERE state_key = 1 AND YR_NUM = 2010'
        ).fetchone()[0]
        self.assertLessEqual(filtered, total)
        self.assertGreater(total, 0, "inpatient is empty")

    def test_year_ranges_match_era(self):
        # MAX era 1 = 2005-2012, MAX era 2 = 2013-2015, TAF = 2016+
        # (upper bound widened to 2025 to accommodate Tier-2a RIF
        # loader, whose Synthea source generates most oncology claims
        # in 2019+).
        bounds = [
            ("inpatient",                 2005, 2012),
            ("inpatient1315",             2013, 2015),
            ("taf_inpatient_header",      2016, 2025),
            ("taf_other_services_header", 2016, 2025),
        ]
        for tbl, y0, y1 in bounds:
            with self.subTest(table=tbl):
                ycol = "YR_NUM" if not tbl.startswith("taf_") else "RFRNC_YR"
                r = self.conn.execute(
                    f'SELECT MIN({ycol}), MAX({ycol}) FROM {tbl}'
                ).fetchone()
                self.assertGreaterEqual(r[0], y0, f"{tbl} min year")
                self.assertLessEqual(r[1], y1, f"{tbl} max year")


class DiabetesPipelineSmoke(unittest.TestCase):
    """Mini-reproduction of the gold-standard pipeline's extraction + filter
    steps.  We don't reproduce the full 24-month cursor logic here — just
    confirm that the shape of each step has positive-count results against
    the synthetic DB."""

    @classmethod
    def setUpClass(cls):
        cls.conn = open_db(DB)

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def test_step1_extract_era1_inpatient_diabetes(self):
        """ICD-9 25x codes in era 1 inpatient."""
        n = self.conn.execute("""
            SELECT COUNT(*) FROM inpatient
            WHERE DIAG_CD_1 LIKE '250%'
              AND YR_NUM BETWEEN 2005 AND 2012
        """).fetchone()[0]
        self.assertGreater(n, 0, "no ICD-9 25x rows in era 1 inpatient")

    def test_step1_extract_era2_inpatient_diabetes(self):
        n = self.conn.execute("""
            SELECT COUNT(*) FROM inpatient1315
            WHERE (DIAG_CD_1 LIKE '250%' OR DIAG_CD_1 LIKE 'E1%')
              AND YR_NUM BETWEEN 2013 AND 2015
        """).fetchone()[0]
        self.assertGreater(n, 0, "no diabetes rows in era 2 inpatient")

    def test_step1_extract_era3_taf_inpatient_diabetes(self):
        n = self.conn.execute("""
            SELECT COUNT(*) FROM taf_inpatient_header
            WHERE DGNS_CD_1 LIKE 'E1%'
              AND RFRNC_YR BETWEEN 2016 AND 2025
        """).fetchone()[0]
        self.assertGreater(n, 0, "no ICD-10 E1x rows in TAF inpatient")

    def test_step3_se_state_filter_reduces_count(self):
        """Step 3 restricts to 7 SE states.  Filtered count must be strictly
        less than the unfiltered count because we intentionally seeded
        wrong_state patients."""
        total = self.conn.execute(
            'SELECT COUNT(*) FROM taf_inpatient_header'
        ).fetchone()[0]
        se = self.conn.execute(f"""
            SELECT COUNT(*) FROM taf_inpatient_header
            WHERE STATE_CD IN ({','.join('?' * len(SE_STATES))})
        """, tuple(SE_STATES)).fetchone()[0]
        self.assertGreater(total, se, "SE-filter didn't drop any rows")
        self.assertGreater(se, 0, "SE filter left zero rows")

    def test_step4_two_year_rule_yields_cohort(self):
        """Per patient, find patients with ≥2 diabetes claims on distinct
        dates within 730 days (24 months).  Our `positive` bucket seeds
        these explicitly, so the cohort must be non-empty."""
        sql = """
            WITH diab_claims AS (
                SELECT BENE_ID, SRVC_BGN_DT AS dt FROM inpatient
                WHERE DIAG_CD_1 LIKE '250%'
                UNION ALL
                SELECT BENE_ID, SRVC_BGN_DT FROM inpatient1315
                WHERE DIAG_CD_1 LIKE '250%' OR DIAG_CD_1 LIKE 'E1%'
                UNION ALL
                SELECT BENE_ID, SRVC_BGN_DT FROM taf_inpatient_header
                WHERE DGNS_CD_1 LIKE 'E1%'
            ),
            paired AS (
                SELECT c1.BENE_ID
                FROM diab_claims c1
                JOIN diab_claims c2 USING (BENE_ID)
                WHERE c1.dt < c2.dt
                  AND (julianday(c2.dt) - julianday(c1.dt)) <= 730
            )
            SELECT COUNT(DISTINCT BENE_ID) FROM paired
        """
        n = self.conn.execute(sql).fetchone()[0]
        self.assertGreater(n, 0, "two-year rule produced empty cohort")

    def test_bucket_labels_consistent(self):
        """wrong_state patients must actually be in a non-SE state.  Since
        we don't persist the bucket label, the test is indirect: at least
        some inpatient patients sit outside SE_STATES."""
        n = self.conn.execute(f"""
            SELECT COUNT(*) FROM inpatient
            WHERE STATE_CD NOT IN ({','.join('?' * len(SE_STATES))})
        """, tuple(SE_STATES)).fetchone()[0]
        self.assertGreater(n, 0, "no wrong_state rows in era 1 inpatient")


class MetaTables(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.conn = open_db(DB)

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def test_data_years_has_19_rows(self):
        # 2005-2023 inclusive = 19 years. Range widened from 14 (2005-2018)
        # in Tier 2a to accommodate RIF claims dated 2019-2023.
        n = self.conn.execute("SELECT COUNT(*) FROM data_years").fetchone()[0]
        self.assertEqual(n, 19)

    def test_data_years_span_2005_2023(self):
        rows = [r[0] for r in self.conn.execute(
            "SELECT year_num FROM data_years ORDER BY year_num")]
        self.assertEqual(rows, list(range(2005, 2024)))

    def test_state_codes_has_60_rows(self):
        n = self.conn.execute("SELECT COUNT(*) FROM state_codes").fetchone()[0]
        self.assertEqual(n, 60)

    def test_table_counts_covers_21_tables(self):
        rows = [r[0] for r in self.conn.execute(
            "SELECT tablename FROM table_counts ORDER BY tablename")]
        self.assertEqual(sorted(rows), sorted(EXPECTED_TABLES))

    def test_table_counts_nonzero_for_populated_tables(self):
        # All six large claim tables + all three demographics tables should be
        # non-empty.
        want = [
            "inpatient", "inpatient1315",
            "other_therapy", "other_therapy1315",
            "taf_inpatient_header", "taf_other_services_header",
            "personal_summary", "personal_summary1315", "taf_demog_elig_base",
        ]
        for t in want:
            with self.subTest(table=t):
                n = self.conn.execute(
                    "SELECT numrows FROM table_counts WHERE tablename = ?",
                    (t,),
                ).fetchone()[0]
                self.assertGreater(n, 0, f"{t} reports 0 rows")


if __name__ == "__main__":
    unittest.main(verbosity=2)
