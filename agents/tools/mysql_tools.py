"""
MySQL tools available to the SQL Writer agent.

execute_sql  — run any SQL on the cms_source DB; returns errors / rows / counts
preview_table — show column list + 3 sample rows of any table
"""
from __future__ import annotations
import re, threading, time

import mysql.connector
from langchain_core.tools import tool

from .sql_split import split_by_delimiter

DB_CFG  = dict(host="127.0.0.1", user="root", database="cms_source")
IGNORABLE_ERRNO = {1305, 1360}   # DROP IF EXISTS on non-existent object
STMT_TIMEOUT    = 30             # seconds before a hanging statement is killed


def _connect():
    return mysql.connector.connect(**DB_CFG)


# Result from the worker thread (all_results, rowcount) or exception
_TIMEOUT_SENTINEL = object()


def _run_stmt_with_timeout(stmt: str):
    """
    Execute *stmt* on a DEDICATED connection in a daemon thread.
    Returns (all_results, rowcount) on success.
    Raises TimeoutError if the statement doesn't finish in STMT_TIMEOUT seconds.
    Raises mysql.connector.Error for MySQL errors.

    Uses a separate connection per call so that the worker thread owns the
    cursor — no cross-thread cursor sharing (mysql-connector cursor is not
    thread-safe).
    """
    result_box = [_TIMEOUT_SENTINEL]   # filled by worker on success
    error_box  = [None]                 # filled by worker on error
    conn_id_box = [None]                # filled by worker once connected
    done       = threading.Event()

    def _worker():
        try:
            con  = mysql.connector.connect(**DB_CFG)
            cur  = con.cursor()
            conn_id_box[0] = con.connection_id
            cur.execute(stmt)

            all_results: list = []
            if cur.description:
                all_results.append(([d[0] for d in cur.description], cur.fetchall()))
            try:
                while cur.nextset():
                    if cur.description:
                        all_results.append(([d[0] for d in cur.description],
                                            cur.fetchall()))
            except Exception:
                pass

            result_box[0] = (all_results, cur.rowcount)
            cur.close()
            try:
                con.commit()
            except Exception:
                pass
            con.close()
        except Exception as e:
            error_box[0] = e
        finally:
            done.set()

    thread = threading.Thread(target=_worker, daemon=True)
    thread.start()

    # Give the worker a moment to establish its connection so we have an ID to kill
    time.sleep(0.05)

    finished = done.wait(STMT_TIMEOUT)

    if not finished:
        # Send KILL QUERY via a fresh connection to unblock the worker
        if conn_id_box[0] is not None:
            try:
                killer = mysql.connector.connect(**DB_CFG)
                kc = killer.cursor()
                kc.execute(f"KILL QUERY {conn_id_box[0]}")
                kc.close()
                killer.close()
            except Exception:
                pass
        done.wait(5)   # give the worker time to see the KILL and exit
        raise TimeoutError(
            f"Statement timed out after {STMT_TIMEOUT}s "
            f"(possible infinite loop in stored procedure)"
        )

    if error_box[0] is not None:
        raise error_box[0]

    return result_box[0]   # (all_results, rowcount)


def _rows_to_text(columns: list[str], rows: list[tuple], max_rows: int = 5) -> str:
    """Format query result as a readable text table."""
    if not rows:
        return "(no rows)"
    col_w = [max(len(c), max((len(str(r[i])) for r in rows), default=0))
             for i, c in enumerate(columns)]
    sep  = "  ".join("-" * w for w in col_w)
    hdr  = "  ".join(c.ljust(w) for c, w in zip(columns, col_w))
    body = "\n".join(
        "  ".join(str(r[i]).ljust(col_w[i]) for i in range(len(columns)))
        for r in rows[:max_rows]
    )
    suffix = f"\n... ({len(rows) - max_rows} more rows not shown)" if len(rows) > max_rows else ""
    return f"{hdr}\n{sep}\n{body}{suffix}"


@tool
def execute_sql(sql: str) -> str:
    """
    Execute one or more MySQL statements against cms_source and return the result.

    Use this tool to:
      1. Explore source tables before writing SQL:
           SELECT * FROM cms_source.inpatient LIMIT 3
      2. Test DDL / stored procedures you have written:
           DROP TABLE IF EXISTS Re_all_inpatient;
           CREATE TABLE Re_all_inpatient (...);
           DELIMITER $$
           CREATE PROCEDURE Re_all_inpatient_loop() ...
           DELIMITER ;
           CALL Re_all_inpatient_loop();
      3. Verify output after running:
           SELECT COUNT(*) FROM Re_all_inpatient;
           SELECT * FROM Re_all_inpatient LIMIT 3;

    Returns a text summary: errors (if any), rows returned (for SELECT),
    or confirmation of statements executed.
    """
    output_parts: list[str] = []
    stmt_count   = 0
    last_select_cols: list[str] = []
    last_select_rows: list[tuple] = []

    for stmt, _is_proc in split_by_delimiter(sql):
        code = re.sub(r"--[^\n]*", "", stmt)
        code = re.sub(r"/\*.*?\*/", "", code, flags=re.DOTALL).strip()
        if not code:
            continue

        kw = code.split()[0].upper() if code.split() else ""
        try:
            all_results, rowcount = _run_stmt_with_timeout(stmt)

            if kw in ("SELECT", "SHOW", "DESCRIBE", "EXPLAIN"):
                if all_results:
                    cols, rows = all_results[-1]
                    last_select_cols = cols
                    last_select_rows = rows
                    output_parts.append(
                        f"SELECT → {len(rows)} row(s)\n"
                        + _rows_to_text(cols, rows)
                    )
            elif kw == "CALL":
                output_parts.append("CALL executed OK")
            else:
                ra = rowcount if rowcount >= 0 else 0
                output_parts.append(f"{kw} OK ({ra} rows affected)")

            stmt_count += 1

        except TimeoutError as e:
            output_parts.append(f"ERROR: {e}")
            break
        except mysql.connector.Error as e:
            if e.errno in IGNORABLE_ERRNO:
                stmt_count += 1
                continue
            output_parts.append(f"ERROR [{e.errno}]: {e.msg}")
            break

    if not output_parts:
        return "No statements executed."
    return f"(Executed {stmt_count} statement(s))\n\n" + "\n\n".join(output_parts)


@tool
def preview_table(table_name: str) -> str:
    """
    Show column names, types, and up to 3 sample rows from a table in cms_source.
    Useful for exploring source table schemas before writing SQL.

    Examples:
      preview_table("inpatient")                  -- source table
      preview_table("Re_all_inpatient")           -- output table you just created
      preview_table("icd_9_cm")                   -- reference table
    """
    try:
        con = _connect()
        cur = con.cursor()
    except mysql.connector.Error as e:
        return f"ERROR: could not connect — {e}"

    lines = []
    # Try qualified and unqualified names
    for name in [table_name, f"cms_source.{table_name}"]:
        try:
            cur.execute(f"DESCRIBE `{name.replace('.', '`.`')}`")
            cols_info = cur.fetchall()
            lines.append(f"Table: {name}")
            lines.append(f"{'Column':<30} {'Type':<20} {'Null':<6} {'Key':<6}")
            lines.append("-" * 64)
            for row in cols_info:
                lines.append(f"{str(row[0]):<30} {str(row[1]):<20} {str(row[2]):<6} {str(row[3]):<6}")

            cur.execute(f"SELECT * FROM `{name.replace('.', '`.`')}` LIMIT 3")
            rows = cur.fetchall()
            col_names = [d[0] for d in cur.description]
            lines.append(f"\nSample rows (up to 3):")
            lines.append(_rows_to_text(col_names, rows, max_rows=3))
            break
        except mysql.connector.Error:
            continue
    else:
        lines.append(f"Table '{table_name}' not found in cms_source.")

    cur.close()
    con.close()
    return "\n".join(lines)


# Export tool list
SQL_TOOLS = [execute_sql, preview_table]
