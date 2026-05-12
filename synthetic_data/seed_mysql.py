"""
seed_mysql.py — Load the synthetic CSVs into MySQL without LOAD DATA LOCAL INFILE.

Use this if your MySQL server won't enable --local-infile=1 (common on
managed hosts).  It's slower than load_mysql.sql but needs no server flags.

Prerequisites:
  1. Run schema_mysql.sql first (creates the 21 tables in the `cms_source` DB).
  2. pip install mysql-connector-python   # pure-Python driver, no C deps.
  3. Generate the CSVs (gen_data.py --csv csv/).

Usage:
  python3 seed_mysql.py \
      --host 127.0.0.1 --port 3306 \
      --user root --password 'secret' \
      --database cms_source \
      --csv-dir ./csv \
      --batch 1000

CSV contract (matches gen_data.py output):
  * First row is the header — its order matches schema_mysql.sql.
  * Fields are comma-separated, RFC-4180 quoted.
  * Empty fields ('' in the CSV) are loaded as SQL NULL for nullable cols,
    and as empty-string '' for NOT NULL VARCHARs.

This script is idempotent: it TRUNCATEs each table before loading.
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
import time
from typing import Iterable, Sequence

try:
    import mysql.connector
    from mysql.connector import errorcode
except ImportError:
    print(
        "ERROR: mysql-connector-python is not installed.\n"
        "       pip install mysql-connector-python",
        file=sys.stderr,
    )
    sys.exit(2)


# Load order matters only for readability — FK checks are off during load.
# Small meta tables first, then large claim tables.
LOAD_ORDER = [
    # meta
    "data_years",
    "state_codes",
    "messagelog",
    "table_counts",
    "table_counts_by_state",
    "table_osline_counts_by_state",
    # MAX claim tables (pre-2013 + 2013-2015)
    "inpatient",
    "inpatient1315",
    "other_therapy",
    "other_therapy1315",
    "personal_summary",
    "personal_summary1315",
    "rx",
    "rx1315",
    # TAF claim tables (2016-2018)
    "taf_demog_elig_base",
    "taf_inpatient_header",
    "taf_inpatient_line",
    "taf_other_services_header",
    "taf_other_services_line",
    "taf_rx_header",
    "taf_rx_line",
]


def get_numeric_columns(cur, database: str, table: str) -> set[str]:
    """Return the set of column names whose declared type is numeric.

    We need this because mysql-connector sends strings as-is; if a CSV
    field is '' and the column is INT, MySQL will reject it.  For numeric
    columns we convert '' → None.  For VARCHAR columns we leave '' alone
    (NOT NULL VARCHAR columns accept '' as a legal value, matching the
    institutional MySQL load behavior).
    """
    cur.execute(
        """
        SELECT COLUMN_NAME, DATA_TYPE
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = %s AND TABLE_NAME = %s
        """,
        (database, table),
    )
    numeric = set()
    for col, dtype in cur.fetchall():
        if dtype.lower() in {
            "int", "bigint", "smallint", "tinyint", "mediumint",
            "decimal", "float", "double", "numeric",
            "date", "datetime", "timestamp", "time", "year",
        }:
            numeric.add(col)
    return numeric


def chunked(rows: Iterable[Sequence], size: int) -> Iterable[list]:
    batch = []
    for row in rows:
        batch.append(row)
        if len(batch) >= size:
            yield batch
            batch = []
    if batch:
        yield batch


def load_table(conn, cur, database: str, table: str, csv_path: str, batch_size: int) -> int:
    if not os.path.exists(csv_path):
        print(f"  [skip] {table}: {csv_path} not found")
        return 0

    numeric_cols = get_numeric_columns(cur, database, table)

    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)

        # Build parameterised INSERT.
        col_list = ", ".join(f"`{c}`" for c in header)
        placeholders = ", ".join(["%s"] * len(header))
        sql = f"INSERT INTO `{table}` ({col_list}) VALUES ({placeholders})"

        # Pre-compute which CSV columns need '' → None conversion.
        is_numeric = [c in numeric_cols for c in header]

        def normalise(row):
            out = []
            for i, v in enumerate(row):
                if is_numeric[i] and v == "":
                    out.append(None)
                else:
                    out.append(v)
            return out

        total = 0
        t0 = time.time()
        for batch in chunked((normalise(r) for r in reader), batch_size):
            cur.executemany(sql, batch)
            total += len(batch)
        conn.commit()
        print(f"  [ok]   {table}: {total:,} rows in {time.time() - t0:.1f}s")
        return total


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=3306)
    p.add_argument("--user", default="root")
    p.add_argument("--password", default="")
    p.add_argument("--database", default="cms_source")
    p.add_argument("--csv-dir", default="./csv")
    p.add_argument("--batch", type=int, default=1000, help="rows per INSERT batch")
    p.add_argument("--only", nargs="*", help="load only these tables (space-separated)")
    args = p.parse_args()

    try:
        conn = mysql.connector.connect(
            host=args.host,
            port=args.port,
            user=args.user,
            password=args.password,
            database=args.database,
            autocommit=False,
            # Keep the packet small enough that we don't need to retune
            # max_allowed_packet but large enough for the 12-col batches.
            allow_local_infile=False,
        )
    except mysql.connector.Error as e:
        if e.errno == errorcode.ER_ACCESS_DENIED_ERROR:
            print("ERROR: access denied — check --user/--password", file=sys.stderr)
        elif e.errno == errorcode.ER_BAD_DB_ERROR:
            print(f"ERROR: database {args.database!r} does not exist. "
                  f"Run schema_mysql.sql first.", file=sys.stderr)
        else:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1

    cur = conn.cursor()
    cur.execute("SET FOREIGN_KEY_CHECKS = 0")
    cur.execute("SET UNIQUE_CHECKS = 0")
    cur.execute("SET SESSION sql_mode = ''")
    conn.commit()

    tables_to_load = [t for t in LOAD_ORDER if not args.only or t in args.only]
    if args.only:
        missing = set(args.only) - set(LOAD_ORDER)
        if missing:
            print(f"ERROR: unknown tables requested: {sorted(missing)}", file=sys.stderr)
            return 1

    grand_total = 0
    for table in tables_to_load:
        # TRUNCATE for idempotence.
        cur.execute(f"TRUNCATE TABLE `{table}`")
        conn.commit()
        csv_path = os.path.join(args.csv_dir, f"{table}.csv")
        grand_total += load_table(conn, cur, args.database, table, csv_path, args.batch)

    cur.execute("SET FOREIGN_KEY_CHECKS = 1")
    cur.execute("SET UNIQUE_CHECKS = 1")
    conn.commit()
    cur.close()
    conn.close()

    print(f"\nLoad complete.  {grand_total:,} rows across {len(tables_to_load)} tables.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
