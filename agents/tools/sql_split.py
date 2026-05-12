"""
sql_split.py — DELIMITER-aware MySQL statement splitter.

Splits a SQL script into a list of (statement_text, was_proc_block) tuples,
correctly handling `DELIMITER $$` blocks containing CREATE PROCEDURE bodies
whose internal `;` must NOT be treated as statement terminators.

Used by:
  - agents/tools/mysql_tools.py (when the SQL Writer agent submits a script
    that contains a stored procedure)
  - any pipeline runner that loads multi-statement .sql files into MySQL
"""
from __future__ import annotations

import re

# MySQL error codes the runners can safely ignore (DROP IF EXISTS on missing
# objects; idempotent re-runs that hit duplicate keys).
IGNORABLE: set[int] = {
    1305,   # PROCEDURE does not exist
    1360,   # TRIGGER does not exist
    1062,   # Duplicate entry
}


def split_by_delimiter(text: str) -> list[tuple[str, bool]]:
    """
    Split SQL text into a list of (statement_text, was_proc_block) tuples.

    Rules:
      - Default delimiter is `;`.
      - `DELIMITER $$` switches to `$$` mode.
      - `DELIMITER ;` switches back to `;` mode.
      - In `;` mode each `;`-terminated line is a standalone statement.
      - In `$$` mode:
          - Lines ending with `;` whose buffer starts with a simple keyword
            (DROP, CALL, SET, …) are standalone statements — flushed.
          - Lines ending with `$$` close a CREATE PROCEDURE/FUNCTION block —
            the entire accumulated block is flushed as one statement
            (was_proc_block=True).

    Handles the canonical pattern:
        DELIMITER $$
        DROP PROCEDURE IF EXISTS proc;
        CREATE PROCEDURE proc() BEGIN ... END$$
        DELIMITER ;
    """
    statements: list[tuple[str, bool]] = []
    current_delim = ';'
    buf: list[str] = []

    # Keywords that start compound statements requiring `$$` to terminate.
    COMPOUND_STARTERS = {'CREATE', 'ALTER', 'BEGIN'}

    lines = text.splitlines(keepends=True)

    for line in lines:
        stripped = line.strip()

        m = re.match(r'^DELIMITER\s+(\S+)\s*(?:--.*)?$', stripped, re.IGNORECASE)
        if m:
            new_delim = m.group(1)
            chunk = ''.join(buf).strip()
            if chunk:
                statements.append((chunk, current_delim != ';'))
            buf = []
            current_delim = new_delim
            continue

        buf.append(line)
        code = re.sub(r'--.*$', '', line).rstrip()

        if current_delim == ';':
            if code.endswith(';'):
                last_clean = code[:-1].rstrip()
                chunk = (''.join(buf[:-1]) + ('\n' + last_clean if last_clean else '')).strip()
                if chunk:
                    statements.append((chunk, False))
                buf = []
        else:
            delim = current_delim
            if code.endswith(delim):
                last_clean = code[:-len(delim)].rstrip()
                chunk = (''.join(buf[:-1]) + ('\n' + last_clean if last_clean else '')).strip()
                if chunk:
                    statements.append((chunk, True))
                buf = []
            elif code.endswith(';'):
                peek = ''.join(buf).strip()
                first_kw = peek.split()[0].upper() if peek.split() else ''
                if first_kw not in COMPOUND_STARTERS:
                    last_clean = code[:-1].rstrip()
                    chunk = (''.join(buf[:-1]) + ('\n' + last_clean if last_clean else '')).strip()
                    if chunk:
                        statements.append((chunk, False))
                    buf = []

    chunk = ''.join(buf).strip()
    if chunk:
        statements.append((chunk, False))

    return statements
