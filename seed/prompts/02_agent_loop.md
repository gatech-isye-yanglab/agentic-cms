# Prompt 02 — Multi-agent prototype: LLM factory + MySQL tool layer

## Goal

Generate `agents/` — the multi-agent prototype. Today this is a
ReAct-style loop driven by an Azure GPT-4o model with two MySQL
tools. The planned 6-node LangGraph DAG (Orchestrator → Schema →
Clinical → SQL Writer → Critic → Assembler) is documented but not
yet split into separate node files.

## Files to generate (under `agents/`)

| File | Purpose |
|---|---|
| `__init__.py` | Empty marker. |
| `llm.py` | Azure OpenAI factory using `DefaultAzureCredential` (no API key needed; reads `PROJECT_ENDPOINT` from env). Pre-builds two singletons: `LLM_STRONG` (gpt-4o, temp=0.0) for orchestrator/sql_writer/assembler and `LLM_FAST` (gpt-4o-mini, temp=0.0) for schema_agent/clinical_agent. |
| `tools/__init__.py` | Empty marker. |
| `tools/mysql_tools.py` | Two LangChain `@tool`-decorated functions: `execute_sql(sql)` and `preview_table(table_name)`. Both target the local `cms_source` MySQL DB. |
| `tools/sql_split.py` | DELIMITER-aware MySQL statement splitter. Pure function; no DB connection. Reused by `mysql_tools.py` and (in prompt 08) by the toy_db runner. |
| `README.md` | Honest about state: ReAct loop today, 6-node DAG planned. Lists the planned node files explicitly as **not yet present**. |

## execute_sql — the load-bearing tool

This is the proposal's defense-in-depth claim. Every statement must
run on a **dedicated** MySQL connection in a **daemon thread**, with a
**30-second timeout**, with `KILL QUERY <conn_id>` issued from a
**separate** connection on hang. The pattern:

```python
def _run_stmt_with_timeout(stmt: str):
    result_box = [_TIMEOUT_SENTINEL]
    error_box = [None]
    conn_id_box = [None]
    done = threading.Event()

    def _worker():
        try:
            con = mysql.connector.connect(**DB_CFG)
            cur = con.cursor()
            conn_id_box[0] = con.connection_id
            cur.execute(stmt)
            # ... fetch all result sets, including via cur.nextset()
            result_box[0] = (all_results, cur.rowcount)
            cur.close(); con.commit(); con.close()
        except Exception as e:
            error_box[0] = e
        finally:
            done.set()

    thread = threading.Thread(target=_worker, daemon=True)
    thread.start()
    time.sleep(0.05)  # let the worker establish its connection
    finished = done.wait(STMT_TIMEOUT)

    if not finished:
        # Send KILL QUERY via a fresh connection to unblock the worker
        if conn_id_box[0] is not None:
            killer = mysql.connector.connect(**DB_CFG)
            kc = killer.cursor()
            kc.execute(f"KILL QUERY {conn_id_box[0]}")
            kc.close(); killer.close()
        done.wait(5)
        raise TimeoutError(...)

    if error_box[0] is not None:
        raise error_box[0]
    return result_box[0]
```

This is what makes the agent "safe" against runaway cursor procedures.
Do not skip it; do not collapse the threading. The KILL must come from
a separate connection because mysql-connector cursors are not
thread-safe within a single connection.

## execute_sql — outer behavior

For each statement (split by `sql_split.split_by_delimiter`):

1. Strip comments via regex (`--…\n` and `/*…*/`).
2. Skip empty statements.
3. Look at the first keyword (`SELECT`, `SHOW`, `DESCRIBE`, `EXPLAIN`,
   `CALL`, or DDL/DML) to format output.
4. Run via `_run_stmt_with_timeout`.
5. Format result:
   - SELECT-like: column names + first 5 rows + total-row-count
   - CALL: "CALL executed OK"
   - Other: "<KW> OK (N rows affected)"
6. Treat MySQL errno 1305 (PROCEDURE does not exist) and 1360
   (TRIGGER does not exist) as ignorable — these are common when
   `DROP PROCEDURE IF EXISTS` runs first.
7. Treat `TimeoutError` and other `mysql.connector.Error` as fatal:
   stop processing remaining statements, return what's been
   collected.

Return string format:
```
(Executed N statement(s))

<formatted result of statement 1>

<formatted result of statement 2>
...
```

## preview_table — schema introspection only

`DESCRIBE <table>` plus `SELECT * FROM <table> LIMIT 3`. Try both the
unqualified name and `cms_source.<name>`. Format as a text table.

## sql_split.split_by_delimiter

Pure function: SQL text → list of `(statement, was_proc_block: bool)`
tuples. Handle `DELIMITER $$` blocks containing CREATE PROCEDURE
bodies whose internal `;` must NOT be treated as statement
terminators. Handle nested standalone statements within `$$` mode
(e.g. `DROP PROCEDURE IF EXISTS p;` followed by `CREATE PROCEDURE
p()...END$$`).

Also export `IGNORABLE = {1305, 1360, 1062}` — MySQL errnos that
runners of multi-statement SQL files can safely skip.

## llm.py — Azure setup

```python
from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from langchain_openai import AzureChatOpenAI

load_dotenv()
_PROJECT_ENDPOINT = os.getenv("PROJECT_ENDPOINT", "")
_AZURE_ENDPOINT = _PROJECT_ENDPOINT.split("/api/projects")[0]
_API_VERSION = "2024-10-01-preview"

def get_llm(deployment: str = "gpt-4o", temperature: float = 0.0):
    return AzureChatOpenAI(
        azure_endpoint=_AZURE_ENDPOINT,
        azure_deployment=deployment,
        api_version=_API_VERSION,
        azure_ad_token_provider=get_bearer_token_provider(
            DefaultAzureCredential(),
            "https://cognitiveservices.azure.com/.default",
        ),
        temperature=temperature,
    )

LLM_STRONG = get_llm("gpt-4o",      temperature=0.0)
LLM_FAST   = get_llm("gpt-4o-mini", temperature=0.0)
```

The deployment names `gpt-4o` and `gpt-4o-mini` are recommendations
to be configured on the user's Azure AI Foundry resource — not
hardcoded resource paths.

## agents/README.md — what to say

State the current state honestly:

> The MVP is a single ReAct-style loop in `tests/test_minimal_extraction.py`,
> NOT separate node files for orchestrator/schema/clinical/sql_writer/critic/assembler.
> Splitting into a 6-node LangGraph DAG is planned grant work.

Do **not** generate stub files for the planned 6 nodes. Empty stubs
are vaporware.

## See also

- The full-repo equivalents at `agents/{llm.py, tools/mysql_tools.py, tools/sql_split.py, README.md}`.
- Prompt 03 for the Critic that consumes the SQL `execute_sql` runs.
- Prompt 08 for the demo tests that exercise this stack end-to-end.
