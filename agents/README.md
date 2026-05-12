# Agents — Multi-Agent Prototype

This folder holds the agent code for translating natural-language biomedical
research questions into validated SQL pipelines against CMS Medicaid claims.

## Current state — what's actually in this folder

The MVP is a **single ReAct-style loop** driven by Azure GPT-4o with two
MySQL tools — `execute_sql` (with a hard statement-timeout-with-`KILL`
fallback) and `preview_table` (schema introspection only). The loop is
implemented as a sequential test driver in
[`../tests/test_minimal_extraction.py`](../tests/test_minimal_extraction.py)
and [`../tests/test_step1_and_2.py`](../tests/test_step1_and_2.py),
*not* as separate node files. Saved traces from real GPT-4o runs are
checked in alongside the tests.

The Critic is implemented as a static-analysis check
([`knowledge/constraints.py`](../knowledge/constraints.py)) plus a live
"output table is non-empty" check after execution. The skill files
([`knowledge/skills/`](../knowledge/skills/)) encode the cursor pattern
and combine-step shape the agent must follow.

The Schema Agent / Clinical Agent / Assembler responsibilities are
**inlined into the SQL Writer's system prompt today**, not separate
nodes. The 6-node DAG below is the architecture the prototype is being
**built toward** — its node files do not exist in this folder yet.

## Planned 6-node DAG (forthcoming)

Splitting the current ReAct loop into a LangGraph DAG with separate
nodes is the planned grant work:

```
User prompt (disease + criteria)
    ↓
Orchestrator → Schema Agent → Clinical Agent → SQL Writer → Critic → Assembler
                                                  ↑           |
                                                  └──── retry ┘
```

Splitting these responsibilities out into separate node files is part
of the proposal's Aim on agent architecture, not yet started.

## What's actually in this folder

| File | Purpose |
|---|---|
| `llm.py` | Azure OpenAI factory using `DefaultAzureCredential` (no API key needed; `az login` + `PROJECT_ENDPOINT` env var). |
| `tools/mysql_tools.py` | `execute_sql` and `preview_table` LangChain tools. `execute_sql` runs each statement on a dedicated connection in a daemon thread with a 30-second timeout; on hang it issues `KILL QUERY` from a separate connection so the worker exits cleanly. |
| `tools/sql_split.py` | DELIMITER-aware MySQL statement splitter. Used by `mysql_tools.py` and by the pipeline runner. |

## Running the demo

The end-to-end demo lives at the repo root in
[`../tests/`](../tests/) and depends on:

1. Local MySQL with a populated `cms_source` schema — use the small
   fixture in [`../toy_db/`](../toy_db/) for fast loops, or the
   schema-exact sandbox in [`../synthetic_data/`](../synthetic_data/)
   for research-scale.
2. Azure AI Foundry access (`az login` + `PROJECT_ENDPOINT` in `.env`).

See the top-level [`../README.md`](../README.md) for the full quickstart
and [`../tests/README.md`](../tests/README.md) for the test layer.

## HIPAA model

The agent runs only against synthetic data. Real claims data lives
behind a VPN + 2FA + VDI institutional HIPAA enclave; a credentialed
human reviewer is the only path into production. See
[`../docs/hipaa.md`](../docs/hipaa.md) for the trust-boundary diagram
and defense-in-depth detail.
