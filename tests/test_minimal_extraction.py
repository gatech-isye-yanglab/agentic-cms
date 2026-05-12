"""
Minimal ReAct agent test — disease-parameterized extraction, with critic retry loop.

Parameterized via knowledge.task_builder: swap the disease module and/or
source_table/era to run a different cohort without editing this file.

  from knowledge.diseases import diabetes as disease   # ← only line to change
  TASK = build_extraction_task(disease=disease, source_table="inpatient", era="ERA1")

What the agent gets:
  - TASK string built from disease profile (ICD codes, table names) +
    shared structural skill (cursor pattern, partition filter constraints)
  - Two tools: execute_sql, preview_table

What the agent does NOT get:
  - Exact column names (must preview_table to discover)
  - ICD filter SQL fragment (must derive from the filter hint in TASK)

If the critic fails, its feedback is passed back to the agent for a retry
(up to MAX_CRITIC_ROUNDS times).

Trace written to: tests/trace_minimal_extraction.txt
  - System prompt + user task: printed in full
  - Tool calls: one-line summary (tool + first 3 lines of arg + result headline)
  - Critic result: pass/fail + row count
"""
import sys, os, datetime
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import mysql.connector
from langchain_core.messages import SystemMessage, HumanMessage, ToolMessage

from agents.llm import LLM_STRONG
from agents.tools.mysql_tools import SQL_TOOLS
from knowledge.constraints import check_partition_filter
from knowledge.task_builder import build_extraction_task
from knowledge.diseases import diabetes as disease

# ── Config ─────────────────────────────────────────────────────────────────────

LLM_WITH_TOOLS  = LLM_STRONG.bind_tools(SQL_TOOLS)
TOOL_MAP        = {t.name: t for t in SQL_TOOLS}
MAX_TOOL_ROUNDS  = 12   # tool calls per agent attempt
MAX_CRITIC_ROUNDS = 3   # critic → agent retry limit

TRACE_PATH = os.path.join(os.path.dirname(__file__), "trace_minimal_extraction.txt")

# ── Prompts ────────────────────────────────────────────────────────────────────

SYSTEM_PROMPT = """You are an expert MySQL developer working on a healthcare claims pipeline.

You have two tools:
  execute_sql(sql)     — run any MySQL statements; returns errors, rows, or execution status
  preview_table(table) — show column names, types, and sample rows for any table in cms_source

Your process:
1. Explore — use the tools to understand the actual table structure before writing anything.
2. Draft   — write the complete SQL for the task.
3. Test    — run it with execute_sql and read the output.
4. Fix     — if there are errors or the output table has 0 rows, diagnose and fix.
5. Output  — once the output table has rows, stop calling tools and output your final SQL
             as plain text only (no markdown fences, no explanation).
"""

# ── Task (built from disease profile + shared skill files) ─────────────────────
# To run a different disease: change the `disease` import above and update
# source_table / era. Everything else (cursor pattern, combine step, etc.) is shared.
TASK = build_extraction_task(
    disease=disease,
    source_table="inpatient",
    era="ERA1",
    year_start=2005,
    year_end=2012,
)

# ── Tracer ─────────────────────────────────────────────────────────────────────

class Tracer:
    """Writes agent trace to stdout and a .txt file.
    Prompts printed in full; tool calls as one-line summaries.
    """

    def __init__(self, path: str):
        self._fh = open(path, "w", encoding="utf-8")

    def _write(self, text: str):
        print(text)
        self._fh.write(text + "\n")
        self._fh.flush()

    # ── structural headers ─────────────────────────────────────────────────────

    def header(self):
        ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        self._write("=" * 72)
        self._write(f"Minimal ReAct Agent — {disease.DISEASE_NAME.title()} Extraction  (with critic retry)")
        self._write(f"Run at: {ts}")
        self._write(f"Disease: {disease.DISEASE_NAME}  |  Source: inpatient  |  ERA: ERA1")
        self._write("Input: disease profile + shared skill files + 2 tools")
        self._write("=" * 72)

    def section(self, title: str):
        self._write(f"\n{'─' * 72}")
        self._write(title)
        self._write("─" * 72)

    # ── full-content blocks ────────────────────────────────────────────────────

    def system_prompt(self):
        self.section("SYSTEM PROMPT")
        self._write(SYSTEM_PROMPT)

    def user_message(self, content: str):
        self.section("USER MESSAGE")
        self._write(content)

    def llm_thinking(self, content: str, round_num: int, attempt: int):
        """LLM plain-text reasoning (no tool calls — this is the final answer round)."""
        self.section(f"LLM FINAL ANSWER  (attempt {attempt}, round {round_num})")
        self._write(content)

    def llm_requests_tools(self, n: int, round_num: int, attempt: int):
        self._write(f"\n[LLM round {round_num} | attempt {attempt}] → requests {n} tool call(s)")

    # ── one-line tool summaries ────────────────────────────────────────────────

    def tool_call(self, tc: dict, result: str, call_num: int):
        arg_val = str(list(tc["args"].values())[0]) if tc["args"] else ""
        # Show tool name + first 3 lines of the SQL input
        input_lines = arg_val.splitlines()
        input_preview = " | ".join(l.strip() for l in input_lines[:3] if l.strip())
        if len(input_lines) > 3:
            input_preview += f"  … ({len(input_lines)} lines total)"
        # Show first 2 lines of result
        result_lines = result.strip().splitlines()
        result_preview = " | ".join(result_lines[:2]) if result_lines else "(empty)"
        self._write(f"  [{call_num:02d}] {tc['name']}: {input_preview}")
        self._write(f"       → {result_preview[:120]}")

    # ── critic ─────────────────────────────────────────────────────────────────

    def critic_result(self, passed: bool, rows: int, patients: int,
                      violations: list[str], attempt: int):
        self.section(f"CRITIC  (attempt {attempt})")
        if violations:
            self._write("  FAIL — partition filter violations:")
            for v in violations:
                self._write(f"    • {v}")
        else:
            self._write("  OK   — partition filter present")
        self._write(f"  rows={rows}  patients={patients}")
        self._write(f"\n  {'PASS' if passed else 'FAIL'}")

    def critic_feedback_sent(self, feedback: str):
        self.section("CRITIC FEEDBACK → sent back to agent")
        self._write(feedback)

    # ── final SQL ──────────────────────────────────────────────────────────────

    def final_sql(self, sql: str, attempt: int):
        self.section(f"GENERATED SQL  (attempt {attempt}, {len(sql.splitlines())} lines)")
        self._write(sql)

    # ── misc ───────────────────────────────────────────────────────────────────

    def log(self, text: str):
        self._write(text)

    def close(self):
        self._fh.close()


# ── Helpers ────────────────────────────────────────────────────────────────────

def _invoke_tool(tc: dict) -> str:
    name = tc["name"]
    if name not in TOOL_MAP:
        return f"Unknown tool: {name}"
    try:
        return TOOL_MAP[name].invoke(tc["args"])
    except Exception as e:
        return f"Tool error: {e}"


def _strip_fences(text: str) -> str:
    if text.startswith("```"):
        text = "\n".join(l for l in text.split("\n") if not l.startswith("```"))
    return text.strip()


def _row_count(table: str) -> tuple[int, int]:
    """Return (total_rows, distinct_patients). Raises on DB error."""
    con = mysql.connector.connect(host="127.0.0.1", user="root", database="cms_source")
    cur = con.cursor()
    cur.execute(f"SELECT COUNT(*), COUNT(DISTINCT patient_id) FROM `{table}`")
    rows, patients = cur.fetchone()
    cur.close()
    con.close()
    return rows, patients


def _build_critic_feedback(violations: list[str], rows: int) -> str:
    lines = ["Your SQL failed the following checks — fix ALL issues and resubmit:"]
    if violations:
        lines.append("")
        lines.append("PARTITION FILTER MISSING:")
        lines.extend(f"  • {v}" for v in violations)
    if rows == 0:
        lines.append("")
        lines.append("OUTPUT TABLE IS EMPTY (0 rows):")
        lines.append("  • The procedure ran without errors but inserted 0 rows.")
        lines.append("  • Common causes:")
        lines.append("      - Wrong column name used in WHERE (e.g. STATE_CD vs state_key)")
        lines.append("      - Nested cursor bug: inner cursor exhaustion sets done=TRUE for outer loop")
        lines.append("      - ICD filter column names don't match the actual source table")
        lines.append("      - data_years filter excludes all rows (check year range vs YR_NUM values)")
    return "\n".join(lines)


# ── Preflight check ───────────────────────────────────────────────────────────

def _preflight_check(tracer: Tracer):
    """Verify MySQL is accessible and required reference tables are populated."""
    try:
        con = mysql.connector.connect(host="127.0.0.1", user="root", database="cms_source")
    except mysql.connector.Error as e:
        tracer.log(f"[PREFLIGHT FAIL] Cannot connect to MySQL: {e}")
        raise SystemExit("Preflight failed — is MySQL running? See above.")
    cur = con.cursor()
    checks = [
        ("icd_9_cm",    "SELECT COUNT(*) FROM icd_9_cm",
         "run: python3 toy_db/run_sql.py"),
        ("state_codes", "SELECT COUNT(*) FROM state_codes",
         "run: python3 toy_db/seed_mysql.py"),
        ("data_years",  "SELECT COUNT(*) FROM data_years",
         "run: python3 toy_db/seed_mysql.py"),
    ]
    ok = True
    for name, sql, hint in checks:
        try:
            cur.execute(sql)
            (n,) = cur.fetchone()
            if n == 0:
                tracer.log(f"[PREFLIGHT FAIL] {name} has 0 rows — {hint}")
                ok = False
            else:
                tracer.log(f"[PREFLIGHT OK]   {name}: {n} rows")
        except mysql.connector.Error as e:
            tracer.log(f"[PREFLIGHT FAIL] {name} error: {e} — {hint}")
            ok = False
    cur.close()
    con.close()
    if not ok:
        raise SystemExit("Preflight failed — see above.")


# ── ReAct agent (one attempt) ──────────────────────────────────────────────────

def run_agent_once(messages: list, tracer: Tracer, attempt: int) -> str:
    """Run the ReAct tool loop once. Returns final SQL string."""
    tool_rounds = 0
    call_num    = 0
    final_sql   = ""

    while tool_rounds < MAX_TOOL_ROUNDS:
        try:
            response = LLM_WITH_TOOLS.invoke(messages)
        except Exception as e:
            tracer.log(f"\n[attempt {attempt}, round {tool_rounds+1}] LLM ERROR: {e}")
            raise
        messages.append(response)

        if not response.tool_calls:
            tracer.llm_thinking(response.content, tool_rounds + 1, attempt)
            final_sql = response.content.strip()
            break

        tracer.llm_requests_tools(len(response.tool_calls), tool_rounds + 1, attempt)
        for tc in response.tool_calls:
            call_num += 1
            result = _invoke_tool(tc)
            tracer.tool_call(tc, result, call_num)
            messages.append(ToolMessage(content=result, tool_call_id=tc["id"]))

        tool_rounds += 1

    else:
        tracer.log(f"\n[attempt {attempt}] MAX_TOOL_ROUNDS reached — forcing final answer")
        messages.append(HumanMessage(
            content="Output your final complete SQL now — raw SQL only, no markdown."
        ))
        try:
            response = LLM_WITH_TOOLS.invoke(messages)
        except Exception as e:
            tracer.log(f"\n[attempt {attempt}, round {tool_rounds+1}] LLM ERROR (force-final): {e}")
            raise
        tracer.llm_thinking(response.content, tool_rounds + 1, attempt)
        final_sql = response.content.strip()

    return _strip_fences(final_sql)


# ── Critic ─────────────────────────────────────────────────────────────────────

def run_critic(sql: str, tracer: Tracer, attempt: int) -> tuple[bool, str]:
    """
    Returns (passed, feedback_text).
    feedback_text is non-empty only when passed=False.
    """
    violations = check_partition_filter(sql, "inpatient")

    try:
        rows, patients = _row_count("Re_all_inpatient")
    except mysql.connector.Error as e:
        rows, patients = 0, 0
        violations.append(f"Table error: {e}")

    passed = not violations and rows > 0
    tracer.critic_result(passed, rows, patients, violations, attempt)

    feedback = "" if passed else _build_critic_feedback(violations, rows)
    return passed, feedback


# ── Main loop ──────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    tracer = Tracer(TRACE_PATH)
    tracer.header()
    tracer.section("PREFLIGHT CHECKS")
    _preflight_check(tracer)
    tracer.system_prompt()

    # Initial message list (grows across retries — agent keeps full history)
    messages: list = [
        SystemMessage(content=SYSTEM_PROMPT),
        HumanMessage(content=TASK),
    ]
    tracer.user_message(TASK)

    final_sql = ""
    passed    = False

    for attempt in range(1, MAX_CRITIC_ROUNDS + 1):
        tracer.log(f"\n{'═' * 72}")
        tracer.log(f"ATTEMPT {attempt} / {MAX_CRITIC_ROUNDS}")
        tracer.log("═" * 72)

        final_sql = run_agent_once(messages, tracer, attempt)
        tracer.final_sql(final_sql, attempt)

        passed, feedback = run_critic(final_sql, tracer, attempt)
        if passed:
            break

        if attempt < MAX_CRITIC_ROUNDS:
            tracer.critic_feedback_sent(feedback)
            # Append critic feedback as a new human turn so the agent can see it
            messages.append(HumanMessage(content=feedback))
        else:
            tracer.log(f"\nMax critic rounds ({MAX_CRITIC_ROUNDS}) reached — stopping.")

    tracer.log(f"\n{'═' * 72}")
    tracer.log(f"FINAL RESULT: {'PASS' if passed else 'FAIL'}  (completed in {attempt} attempt(s))")
    tracer.log("═" * 72)
    tracer.log(f"\nTrace saved to: {TRACE_PATH}")
    tracer.close()
