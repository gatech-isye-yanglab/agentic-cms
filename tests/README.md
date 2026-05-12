# Agent Demonstration Tests

End-to-end tests of the multi-agent prototype on the small `cms_source`
fixture in [`../toy_db/`](../toy_db/).

These are **demonstration tests**, not unit tests — each one drives a
real GPT-4o ReAct loop against MySQL, and a successful run leaves a
saved trace file alongside the test. The trace captures every prompt,
tool call, critic feedback round, and the final generated SQL, so a
reviewer cloning the repo can see what the agent actually does without
having to spin up Azure access themselves.

(For the smaller, dependency-light tests of the synthetic CMS sandbox,
see [`../synthetic_data/tests/`](../synthetic_data/tests/) — those run
under plain pytest with no external services.)

## Tests

| Test | What it does | Saved trace |
|---|---|---|
| [`test_minimal_extraction.py`](test_minimal_extraction.py) | Single-step ReAct loop: extract a diabetes cohort from the ERA1 inpatient table. The agent gets a disease profile + skill files + 2 tools (`execute_sql`, `preview_table`), then has up to 3 critic-retry rounds to produce a partition-filtered cursor procedure that returns >0 rows. | [`trace_minimal_extraction.txt`](trace_minimal_extraction.txt) |
| [`test_step1_and_2.py`](test_step1_and_2.py) | Full Step 1 + Step 2 — three ERAs (ERA1 / ERA2 / ERA3 TAF) extracted sequentially, then unioned into `all_combine`. Each step has up to 3 critic-retry rounds. | [`trace_step1_and_2.txt`](trace_step1_and_2.txt) |

## Saved traces — what they show

Both `.txt` files are saved outputs from real runs of the prototype.
Each one captures:

1. The system prompt and user task built from
   [`knowledge/task_builder.py`](../knowledge/task_builder.py) +
   [`knowledge/skills/`](../knowledge/skills/).
2. The agent's tool calls in order — `preview_table` to discover schema,
   `execute_sql` to test cursor procedures, with one-line summaries of
   each call's arguments and result.
3. Critic feedback when partition filters or output row counts fail
   the static checks in
   [`knowledge/constraints.py`](../knowledge/constraints.py).
4. The final generated SQL the agent settled on.
5. A `FINAL RESULT: PASS` / `FAIL` line.

Reading these is the cheapest way to see what the prototype is doing
end-to-end without Azure credentials or local MySQL.

## Running them yourself

Prerequisites:

1. **Python deps:**
   ```bash
   pip install langchain langchain-openai langchain-core langchain-community \
               mysql-connector-python azure-identity python-dotenv
   ```

2. **Local MySQL with the `cms_source` fixture:**
   ```bash
   python3 toy_db/seed_mysql.py     # creates schema + ~1,400 rows
   python3 toy_db/run_sql.py        # loads reference + Step-2/3/4 SQL
   ```

3. **Azure OpenAI access** — `az login` + a `PROJECT_ENDPOINT` in `.env`
   (see [`.env.example`](../.env.example)).

Then:

```bash
python3 tests/test_minimal_extraction.py
# Expected: FINAL RESULT: PASS  (trace overwrites tests/trace_minimal_extraction.txt)

python3 tests/test_step1_and_2.py
# Expected: OVERALL: PASS       (trace overwrites tests/trace_step1_and_2.txt)
```

## What "passing" means

A test passes when the agent's generated SQL:

1. Includes the partition filter (`state_key` + `YR_NUM` / `RFRNC_YR`)
   on every read against a `cms_source` source table — verified by
   [`knowledge.constraints.check_partition_filter`](../knowledge/constraints.py).
2. Produces a non-empty output table after execution — verified by a
   live `SELECT COUNT(*)` against the result table.
3. Both checks pass within at most 3 critic-retry rounds.

The "ReAct loop with critic retry" pattern this exercises is the
**MVP of the planned 6-node DAG** — the Schema Agent / Clinical Agent /
Assembler responsibilities currently live inside the SQL Writer's
system prompt; splitting them out into separate LangGraph nodes is the
planned grant work. See [`../agents/README.md`](../agents/README.md).
