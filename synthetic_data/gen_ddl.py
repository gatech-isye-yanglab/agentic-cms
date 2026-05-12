"""
gen_ddl.py — Parse `columns_formats.csv` (the institutional schema export)
and emit:
    schema_mysql.sql  — 21 CREATE TABLEs in original MySQL types
    schema_sqlite.sql — same tables translated to SQLite affinities

Column order, column names (case preserved), and nullability are preserved
exactly as in the export.  Every table lives in the `cms_source` schema (for
MySQL the schema is set via USE; for SQLite we simply drop the schema prefix
since SQLite has no schemas).

Usage (run from this directory):
    python3 gen_ddl.py
"""

import csv
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, "columns_formats.csv")
OUT_MYSQL  = os.path.join(HERE, "schema_mysql.sql")
OUT_SQLITE = os.path.join(HERE, "schema_sqlite.sql")


def mysql_to_sqlite(full_type: str) -> str:
    """Translate a MySQL column type into SQLite-friendly affinity.

    SQLite uses dynamic typing — the declared type is advisory.  We keep the
    affinity reasonable so CAST, comparisons, and ORDER BY behave predictably.
    """
    t = full_type.strip().lower()
    if t == "date" or t == "timestamp":
        return "TEXT"
    if t.startswith("varchar"):
        return "TEXT"
    if t.startswith("decimal"):
        return "REAL"
    if t.startswith("int"):
        return "INTEGER"
    if t.startswith("bigint"):
        return "INTEGER"
    if t.startswith("tinyint"):
        return "INTEGER"
    # Fallback — SQLite treats unknown types as BLOB affinity; log and fail so
    # we never silently misroute a column.
    raise ValueError(f"unhandled MySQL type: {full_type!r}")


def parse_schema(csv_path: str):
    """Return an ordered mapping: table_name -> list of (col_name, full_type, is_nullable)."""
    tables = defaultdict(list)
    # Preserve first-seen table ordering for nicer DDL.
    table_order = []
    with open(csv_path, newline="") as f:
        r = csv.DictReader(f)
        for row in r:
            tname = row["table_name"]
            if tname not in tables:
                table_order.append(tname)
            tables[tname].append((
                int(row["column_order"]),
                row["column_name"],
                row["full_type"],
                row["is_nullable"].strip().upper() == "YES",
            ))
    # Sort columns by column_order inside each table.
    for tname in tables:
        tables[tname].sort(key=lambda c: c[0])
    return table_order, tables


def escape_ident_mysql(name: str) -> str:
    return f"`{name}`"


def escape_ident_sqlite(name: str) -> str:
    # SQLite accepts `"name"` or `[name]`.  Double quotes is SQL standard.
    return '"' + name.replace('"', '""') + '"'


def build_mysql_ddl(table_order, tables) -> str:
    out = []
    out.append("-- schema_mysql.sql — auto-generated from columns_formats.csv")
    out.append("-- Do not hand-edit; re-run gen_ddl.py to regenerate.")
    out.append("--")
    out.append("-- Creates the 21-table `cms_source` schema for local MySQL.")
    out.append("-- Connection hint: DBMS connection read timeout → 600 s.")
    out.append("")
    out.append("CREATE DATABASE IF NOT EXISTS cms_source")
    out.append("  DEFAULT CHARACTER SET utf8mb4")
    out.append("  DEFAULT COLLATE utf8mb4_unicode_ci;")
    out.append("USE cms_source;")
    out.append("")
    for tname in table_order:
        out.append(f"DROP TABLE IF EXISTS {escape_ident_mysql(tname)};")
        out.append(f"CREATE TABLE {escape_ident_mysql(tname)} (")
        col_lines = []
        for _, cname, full_type, nullable in tables[tname]:
            null_clause = "" if nullable else " NOT NULL"
            col_lines.append(f"  {escape_ident_mysql(cname)} {full_type}{null_clause}")
        out.append(",\n".join(col_lines))
        out.append(") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;")
        out.append("")
    # Helpful indexes on the partition-filter columns (state_key + year).
    out.append("-- Partition-filter indexes (production queries require these).")
    partition_idx = [
        ("inpatient",            "state_key", "YR_NUM"),
        ("inpatient1315",        "state_key", "YR_NUM"),
        ("other_therapy",        "state_key", "YR_NUM"),
        ("other_therapy1315",    "state_key", "YR_NUM"),
        ("rx",                   "state_key", "YR_NUM"),
        ("rx1315",               "state_key", "YR_NUM"),
        ("personal_summary",     "state_key", "MAX_YR_DT"),
        ("personal_summary1315", "state_key", "MAX_YR_DT"),
        ("taf_demog_elig_base",      "STATE_KEY", None),
        ("taf_inpatient_header",     "STATE_KEY", None),
        ("taf_inpatient_line",       "STATE_KEY", None),
        ("taf_other_services_header","STATE_KEY", None),
        ("taf_other_services_line",  "STATE_KEY", None),
        ("taf_rx_header",            "STATE_KEY", None),
        ("taf_rx_line",              "STATE_KEY", None),
    ]
    for tname, c1, c2 in partition_idx:
        if c2:
            out.append(
                f"CREATE INDEX idx_{tname}_partition "
                f"ON {escape_ident_mysql(tname)} "
                f"({escape_ident_mysql(c1)}, {escape_ident_mysql(c2)});"
            )
        else:
            out.append(
                f"CREATE INDEX idx_{tname}_state_key "
                f"ON {escape_ident_mysql(tname)} ({escape_ident_mysql(c1)});"
            )
    out.append("")
    return "\n".join(out)


def build_sqlite_ddl(table_order, tables) -> str:
    out = []
    out.append("-- schema_sqlite.sql — auto-generated from columns_formats.csv")
    out.append("-- Do not hand-edit; re-run gen_ddl.py to regenerate.")
    out.append("--")
    out.append("-- Sandbox-friendly schema.  SQLite has no namespaces, so")
    out.append("-- every table becomes top-level (queries that say")
    out.append("-- `cms_source.table` need a view or stripped prefix).")
    out.append("")
    out.append("PRAGMA foreign_keys = OFF;")
    out.append("PRAGMA journal_mode = MEMORY;")
    out.append("BEGIN;")
    out.append("")
    for tname in table_order:
        out.append(f"DROP TABLE IF EXISTS {escape_ident_sqlite(tname)};")
        out.append(f"CREATE TABLE {escape_ident_sqlite(tname)} (")
        col_lines = []
        for _, cname, full_type, nullable in tables[tname]:
            affinity = mysql_to_sqlite(full_type)
            null_clause = "" if nullable else " NOT NULL"
            col_lines.append(f"  {escape_ident_sqlite(cname)} {affinity}{null_clause}")
        out.append(",\n".join(col_lines))
        out.append(");")
        out.append("")
    # Same indexes, sqlite-quoted.
    out.append("-- Partition-filter indexes.")
    partition_idx = [
        ("inpatient",            "state_key", "YR_NUM"),
        ("inpatient1315",        "state_key", "YR_NUM"),
        ("other_therapy",        "state_key", "YR_NUM"),
        ("other_therapy1315",    "state_key", "YR_NUM"),
        ("rx",                   "state_key", "YR_NUM"),
        ("rx1315",               "state_key", "YR_NUM"),
        ("personal_summary",     "state_key", "MAX_YR_DT"),
        ("personal_summary1315", "state_key", "MAX_YR_DT"),
        ("taf_demog_elig_base",      "STATE_KEY", None),
        ("taf_inpatient_header",     "STATE_KEY", None),
        ("taf_inpatient_line",       "STATE_KEY", None),
        ("taf_other_services_header","STATE_KEY", None),
        ("taf_other_services_line",  "STATE_KEY", None),
        ("taf_rx_header",            "STATE_KEY", None),
        ("taf_rx_line",              "STATE_KEY", None),
    ]
    for tname, c1, c2 in partition_idx:
        if c2:
            out.append(
                f"CREATE INDEX idx_{tname}_partition "
                f"ON {escape_ident_sqlite(tname)} "
                f"({escape_ident_sqlite(c1)}, {escape_ident_sqlite(c2)});"
            )
        else:
            out.append(
                f"CREATE INDEX idx_{tname}_state_key "
                f"ON {escape_ident_sqlite(tname)} ({escape_ident_sqlite(c1)});"
            )
    out.append("")
    out.append("COMMIT;")
    out.append("")
    return "\n".join(out)


def main():
    table_order, tables = parse_schema(SRC)
    if len(table_order) != 21:
        print(f"WARNING: expected 21 tables, got {len(table_order)}", file=sys.stderr)
    mysql_sql  = build_mysql_ddl(table_order, tables)
    sqlite_sql = build_sqlite_ddl(table_order, tables)
    with open(OUT_MYSQL, "w") as f:
        f.write(mysql_sql)
    with open(OUT_SQLITE, "w") as f:
        f.write(sqlite_sql)
    total_cols = sum(len(cs) for cs in tables.values())
    print(f"Wrote {OUT_MYSQL}  ({len(mysql_sql.splitlines())} lines)")
    print(f"Wrote {OUT_SQLITE} ({len(sqlite_sql.splitlines())} lines)")
    print(f"Tables: {len(table_order)}   Columns: {total_cols}")


if __name__ == "__main__":
    main()
