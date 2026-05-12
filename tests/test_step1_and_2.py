"""
Step 1 + 2 pipeline test: 3-ERA inpatient extraction → all_combine.

Step 1  (agent × 3):
  ERA1  cms_source.inpatient            → Re_all_inpatient
  ERA2  cms_source.inpatient1315        → Re_all_inpatient1315
  ERA3  cms_source.taf_inpatient_header → Re_All_taf_inpatient_header

Step 2  (direct SQL — disease-agnostic):
  Union the 3 extraction tables → all_combine
  Column mapping adapts to whatever column names the agent produced.

Critic per step: partition filter check + row count > 0.
Final validation: all_combine row count and per-era breakdown.

Trace: tests/trace_step1_and_2.txt
"""
import sys, os, datetime
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import mysql.connector
from langchain_core.messages import SystemMessage, HumanMessage, ToolMessage

from agents.llm import LLM_STRONG
from agents.tools.mysql_tools import SQL_TOOLS, execute_sql
from knowledge.constraints import check_partition_filter
from knowledge.task_builder import build_extraction_task
from knowledge.diseases import diabetes as disease

# ── Config ─────────────────────────────────────────────────────────────────────

LLM_WITH_TOOLS   = LLM_STRONG.bind_tools(SQL_TOOLS)
TOOL_MAP         = {t.name: t for t in SQL_TOOLS}
MAX_TOOL_ROUNDS  = 14   # tool calls per agent attempt
MAX_CRITIC_ROUNDS = 3   # critic → agent retry limit

TRACE_PATH = os.path.join(os.path.dirname(__file__), "trace_step1_and_2.txt")

# 3 extraction steps in order
EXTRACTION_STEPS = [
    dict(source_table="inpatient",             era="ERA1", year_start=2005, year_end=2012),
    dict(source_table="inpatient1315",          era="ERA2", year_start=2013, year_end=2015),
    dict(source_table="taf_inpatient_header",   era="ERA3", year_start=2016, year_end=2018),
]

# ── Shared system prompt ────────────────────────────────────────────────────────

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

# ── Tracer ─────────────────────────────────────────────────────────────────────

class Tracer:
    def __init__(self, path: str):
        self._fh = open(path, "w", encoding="utf-8")

    def _write(self, text: str):
        print(text)
        self._fh.write(text + "\n")
        self._fh.flush()

    def header(self):
        ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        self._write("=" * 72)
        self._write(f"Step 1+2 Pipeline — {disease.DISEASE_NAME.title()} Inpatient (3 ERAs → all_combine)")
        self._write(f"Run at: {ts}")
        self._write("=" * 72)

    def section(self, title: str):
        self._write(f"\n{'─' * 72}")
        self._write(title)
        self._write("─" * 72)

    def step_banner(self, step_num: int, label: str):
        self._write(f"\n{'█' * 72}")
        self._write(f"  STEP {step_num}: {label}")
        self._write("█" * 72)

    def attempt_banner(self, attempt: int, total: int):
        self._write(f"\n{'═' * 72}")
        self._write(f"ATTEMPT {attempt} / {total}")
        self._write("═" * 72)

    def system_prompt(self):
        self.section("SYSTEM PROMPT")
        self._write(SYSTEM_PROMPT)

    def user_message(self, content: str):
        self.section("USER MESSAGE (TASK)")
        self._write(content)

    def llm_thinking(self, content: str, round_num: int, attempt: int):
        self.section(f"LLM FINAL ANSWER  (attempt {attempt}, round {round_num})")
        self._write(content)

    def llm_requests_tools(self, n: int, round_num: int, attempt: int):
        self._write(f"\n[LLM round {round_num} | attempt {attempt}] → requests {n} tool call(s)")

    def tool_call(self, tc: dict, result: str, call_num: int):
        arg_val = str(list(tc["args"].values())[0]) if tc["args"] else ""
        input_lines = arg_val.splitlines()
        input_preview = " | ".join(l.strip() for l in input_lines[:3] if l.strip())
        if len(input_lines) > 3:
            input_preview += f"  … ({len(input_lines)} lines total)"
        result_lines = result.strip().splitlines()
        result_preview = " | ".join(result_lines[:2]) if result_lines else "(empty)"
        self._write(f"  [{call_num:02d}] {tc['name']}: {input_preview}")
        self._write(f"       → {result_preview[:120]}")

    def critic_result(self, passed: bool, rows: int, patients: int,
                      violations: list, attempt: int):
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

    def final_sql(self, sql: str, attempt: int):
        self.section(f"GENERATED SQL  (attempt {attempt}, {len(sql.splitlines())} lines)")
        self._write(sql)

    def combine_sql(self, sql: str):
        self.section(f"COMBINE SQL  ({len(sql.splitlines())} lines)")
        self._write(sql)

    def log(self, text: str):
        self._write(text)

    def close(self):
        self._fh.close()


# ── Helpers ────────────────────────────────────────────────────────────────────

def _connect():
    return mysql.connector.connect(host="127.0.0.1", user="root", database="cms_source")


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
    con = _connect()
    cur = con.cursor()
    cur.execute(f"SELECT COUNT(*), COUNT(DISTINCT patient_id) FROM `{table}`")
    rows, patients = cur.fetchone()
    cur.close(); con.close()
    return rows, patients


def _get_columns(table: str) -> list[str]:
    con = _connect()
    cur = con.cursor()
    cur.execute(f"DESCRIBE `{table}`")
    cols = [r[0] for r in cur.fetchall()]
    cur.close(); con.close()
    return cols


def _build_critic_feedback(violations: list, rows: int) -> str:
    lines = ["Your SQL failed the following checks — fix ALL issues and resubmit:"]
    if violations:
        lines += ["", "PARTITION FILTER MISSING:"]
        lines += [f"  • {v}" for v in violations]
    if rows == 0:
        lines += [
            "", "OUTPUT TABLE IS EMPTY (0 rows):",
            "  • The procedure ran without errors but inserted 0 rows.",
            "  • Common causes:",
            "      - Wrong column name in WHERE (e.g. STATE_CD vs state_key vs STATE_KEY)",
            "      - Wrong year column (YR_NUM vs RFRNC_YR)",
            "      - Nested cursor bug: inner cursor exhaustion sets done=1 for outer loop",
            "      - ICD filter column names don't match the actual source table",
            "      - data_years filter year range excludes all rows",
        ]
    return "\n".join(lines)


# ── Preflight ──────────────────────────────────────────────────────────────────

def _preflight_check(tracer: Tracer):
    try:
        con = _connect()
    except mysql.connector.Error as e:
        tracer.log(f"[PREFLIGHT FAIL] Cannot connect to MySQL: {e}")
        raise SystemExit("Preflight failed — is MySQL running?")
    cur = con.cursor()
    checks = [
        ("icd_9_cm",    "SELECT COUNT(*) FROM icd_9_cm",    "python3 toy_db/run_sql.py"),
        ("state_codes", "SELECT COUNT(*) FROM state_codes", "python3 toy_db/seed_mysql.py"),
        ("data_years",  "SELECT COUNT(*) FROM data_years",  "python3 toy_db/seed_mysql.py"),
    ]
    for src_tbl in ["inpatient", "inpatient1315", "taf_inpatient_header"]:
        checks.append((src_tbl, f"SELECT COUNT(*) FROM {src_tbl}", "python3 toy_db/seed_mysql.py"))
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
    cur.close(); con.close()
    if not ok:
        raise SystemExit("Preflight failed — see above.")


# ── ReAct agent (one attempt) ──────────────────────────────────────────────────

def run_agent_once(messages: list, tracer: Tracer, attempt: int) -> str:
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
        messages.append(HumanMessage(content="Output your final complete SQL now — raw SQL only, no markdown."))
        try:
            response = LLM_WITH_TOOLS.invoke(messages)
        except Exception as e:
            tracer.log(f"\n[attempt {attempt}, round {tool_rounds+1}] LLM ERROR (force-final): {e}")
            raise
        tracer.llm_thinking(response.content, tool_rounds + 1, attempt)
        final_sql = response.content.strip()

    return _strip_fences(final_sql)


# ── Critic ─────────────────────────────────────────────────────────────────────

def run_critic(sql: str, source_table: str, output_table: str,
               tracer: Tracer, attempt: int) -> tuple[bool, str]:
    violations = check_partition_filter(sql, source_table)
    try:
        rows, patients = _row_count(output_table)
    except mysql.connector.Error as e:
        rows, patients = 0, 0
        violations.append(f"Table error: {e}")

    passed = not violations and rows > 0
    tracer.critic_result(passed, rows, patients, violations, attempt)
    feedback = "" if passed else _build_critic_feedback(violations, rows)
    return passed, feedback


# ── Combine step (direct SQL, no agent) ───────────────────────────────────────

def build_combine_sql() -> str:
    """
    Build all_combine INSERT SQL by inspecting actual extraction output table
    columns. Adapts to whatever column names the agent produced.
    """
    create_ddl = """\
DROP TABLE IF EXISTS all_combine;
CREATE TABLE all_combine (
  patient_id   VARCHAR(40),
  BENE_ID      VARCHAR(15),
  STATE_CD     VARCHAR(2),
  state_key    INT,
  YR_NUM       INT,
  BIRTH_DT     DATE,
  srvc_bgn_dt  DATE,
  srvc_end_dt  DATE,
  DIAG_CD_1    VARCHAR(8),
  DIAG_CD_2    VARCHAR(8),
  DIAG_CD_3    VARCHAR(8),
  DIAG_CD_4    VARCHAR(8),
  DIAG_CD_5    VARCHAR(8),
  DIAG_CD_6    VARCHAR(8),
  DIAG_CD_7    VARCHAR(8),
  DIAG_CD_8    VARCHAR(8),
  DIAG_CD_9    VARCHAR(8),
  DIAG_CD_10   VARCHAR(7),
  DIAG_CD_11   VARCHAR(7),
  DIAG_CD_12   VARCHAR(7)
);\
"""
    inserts = []

    # ── ERA1 / ERA2: DIAG_CD_1..9, patient_id (lower), EL_DOB → BIRTH_DT ────
    for table in ["Re_all_inpatient", "Re_all_inpatient1315"]:
        cols = _get_columns(table)
        cols_up = {c.upper(): c for c in cols}

        pid  = cols_up.get("PATIENT_ID", cols_up.get("patient_id".upper(), "patient_id"))
        bid  = cols_up.get("BENE_ID", "BENE_ID")
        scd  = cols_up.get("STATE_CD", "STATE_CD")
        sk   = cols_up.get("STATE_KEY", "state_key")
        yr   = cols_up.get("YR_NUM", "YR_NUM")
        dob  = cols_up.get("EL_DOB", cols_up.get("BIRTH_DT", "EL_DOB"))
        sbd  = cols_up.get("SRVC_BGN_DT", "srvc_bgn_dt")
        sed  = cols_up.get("SRVC_END_DT", "srvc_end_dt")
        diag = [cols_up[f"DIAG_CD_{i}"] for i in range(1, 10) if f"DIAG_CD_{i}" in cols_up]

        n = len(diag)
        tgt = ", ".join(f"DIAG_CD_{i}" for i in range(1, n + 1))
        src = ", ".join(diag)

        inserts.append(
            f"-- {table} (ERA1/ERA2: {n} diag cols, {dob}→BIRTH_DT)\n"
            f"INSERT INTO all_combine (patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, BIRTH_DT,\n"
            f"  srvc_bgn_dt, srvc_end_dt, {tgt})\n"
            f"SELECT {pid}, {bid}, {scd}, {sk}, {yr}, {dob},\n"
            f"  {sbd}, {sed}, {src}\n"
            f"FROM {table};"
        )

    # ── ERA3: DGNS_CD_1..12 → DIAG_CD_1..12, RFRNC_YR → YR_NUM ─────────────
    table = "Re_All_taf_inpatient_header"
    cols = _get_columns(table)
    cols_up = {c.upper(): c for c in cols}

    pid  = cols_up.get("PATIENT_ID", "PATIENT_ID")
    bid  = cols_up.get("BENE_ID", "BENE_ID")
    scd  = cols_up.get("STATE_CD", "STATE_CD")
    sk   = cols_up.get("STATE_KEY", cols_up.get("state_key".upper(), "STATE_KEY"))
    yr   = cols_up.get("RFRNC_YR", "RFRNC_YR")
    dob  = cols_up.get("BIRTH_DT", "BIRTH_DT")
    sbd  = cols_up.get("SRVC_BGN_DT", "srvc_bgn_dt")
    sed  = cols_up.get("SRVC_END_DT", "srvc_end_dt")
    dgns = [cols_up[f"DGNS_CD_{i}"] for i in range(1, 13) if f"DGNS_CD_{i}" in cols_up]

    n = len(dgns)
    tgt = ", ".join(f"DIAG_CD_{i}" for i in range(1, n + 1))
    src = ", ".join(dgns)

    inserts.append(
        f"-- {table} (ERA3: {n} DGNS_CD_ cols → DIAG_CD_, {yr}→YR_NUM)\n"
        f"INSERT INTO all_combine (patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, BIRTH_DT,\n"
        f"  srvc_bgn_dt, srvc_end_dt, {tgt})\n"
        f"SELECT {pid}, {bid}, {scd}, {sk}, {yr}, {dob},\n"
        f"  {sbd}, {sed}, {src}\n"
        f"FROM {table};"
    )

    return create_ddl + "\n\n" + "\n\n".join(inserts)


def run_combine_step(tracer: Tracer) -> tuple[bool, int]:
    """Execute the combine step. Returns (success, total_rows)."""
    tracer.step_banner(2, "Combine → all_combine  (direct SQL, no agent)")

    sql = build_combine_sql()
    tracer.combine_sql(sql)

    result = execute_sql.invoke({"sql": sql})
    tracer.section("COMBINE EXECUTION RESULT")
    tracer.log(result)

    if "ERROR" in result:
        tracer.log("\n  COMBINE FAILED")
        return False, 0

    # Verify row counts per era
    try:
        con = _connect()
        cur = con.cursor()
        cur.execute("SELECT COUNT(*), COUNT(DISTINCT patient_id) FROM all_combine")
        total_rows, total_pts = cur.fetchone()
        tracer.section("COMBINE VALIDATION")
        tracer.log(f"  all_combine total: {total_rows} rows, {total_pts} distinct patients")

        # Row counts per year range
        for label, yr_min, yr_max in [
            ("ERA1 (2005-2012)", 2005, 2012),
            ("ERA2 (2013-2015)", 2013, 2015),
            ("ERA3 (2016-2018)", 2016, 2018),
        ]:
            cur.execute(
                "SELECT COUNT(*) FROM all_combine WHERE YR_NUM BETWEEN %s AND %s",
                (yr_min, yr_max)
            )
            (n,) = cur.fetchone()
            tracer.log(f"  {label}: {n} rows")

        cur.close(); con.close()
        passed = total_rows > 0
        tracer.log(f"\n  {'PASS' if passed else 'FAIL — all_combine is empty'}")
        return passed, total_rows
    except mysql.connector.Error as e:
        tracer.log(f"\n  COMBINE VALIDATION ERROR: {e}")
        return False, 0


# ── Main ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    tracer = Tracer(TRACE_PATH)
    tracer.header()
    tracer.section("PREFLIGHT CHECKS")
    _preflight_check(tracer)
    tracer.system_prompt()

    extraction_results = {}   # source_table → (passed, rows)
    all_passed = True

    # ── Step 1: 3 ERA extractions ──────────────────────────────────────────────
    for step_num, step in enumerate(EXTRACTION_STEPS, start=1):
        src   = step["source_table"]
        era   = step["era"]
        ys    = step["year_start"]
        ye    = step["year_end"]
        out   = disease.OUTPUT_TABLE_MAP[src]

        tracer.step_banner(step_num, f"{era} — {src} → {out}")

        task = build_extraction_task(disease=disease, source_table=src, era=era,
                                     year_start=ys, year_end=ye)

        messages: list = [
            SystemMessage(content=SYSTEM_PROMPT),
            HumanMessage(content=task),
        ]
        tracer.user_message(task)

        step_passed = False
        for attempt in range(1, MAX_CRITIC_ROUNDS + 1):
            tracer.attempt_banner(attempt, MAX_CRITIC_ROUNDS)
            final_sql = run_agent_once(messages, tracer, attempt)
            tracer.final_sql(final_sql, attempt)

            step_passed, feedback = run_critic(final_sql, src, out, tracer, attempt)
            if step_passed:
                break

            if attempt < MAX_CRITIC_ROUNDS:
                tracer.critic_feedback_sent(feedback)
                messages.append(HumanMessage(content=feedback))
            else:
                tracer.log(f"\nMax critic rounds ({MAX_CRITIC_ROUNDS}) reached — stopping.")

        rows, _ = _row_count(out) if step_passed else (0, 0)
        extraction_results[src] = (step_passed, rows)
        if not step_passed:
            all_passed = False
            tracer.log(f"\n[ABORT] {era} extraction failed — skipping combine step.")
            break

    # ── Step 2: Combine ────────────────────────────────────────────────────────
    combine_passed = False
    if all_passed:
        combine_passed, combine_rows = run_combine_step(tracer)

    # ── Final summary ─────────────────────────────────────────────────────────
    tracer.log(f"\n{'═' * 72}")
    tracer.log("FINAL SUMMARY")
    tracer.log("═" * 72)
    for step, src in enumerate(EXTRACTION_STEPS, start=1):
        src_tbl = src["source_table"]
        out_tbl = disease.OUTPUT_TABLE_MAP[src_tbl]
        ok, rows = extraction_results.get(src_tbl, (False, 0))
        tracer.log(f"  Step 1{chr(96+step)} {src['era']}  {src_tbl} → {out_tbl}: "
                   f"{'PASS' if ok else 'FAIL'}  ({rows} rows)")
    if all_passed:
        tracer.log(f"  Step 2   Combine → all_combine: {'PASS' if combine_passed else 'FAIL'}")
    tracer.log(f"\n  OVERALL: {'PASS' if (all_passed and combine_passed) else 'FAIL'}")
    tracer.log("═" * 72)
    tracer.log(f"\nTrace saved to: {TRACE_PATH}")
    tracer.close()
