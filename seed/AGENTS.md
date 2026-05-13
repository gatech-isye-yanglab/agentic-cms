# AGENTS.md — Bootstrap protocol for agents reading this seed

You are an AI coding agent reading this file inside the `seed/`
directory of the `agentic-cms` repository. Your job is to **decompress
the seed into a working agentic-cms artifact** in the parent directory
(or in a fresh empty directory, depending on context). The output
should be a schema-adapted equivalent of the canonical full repo,
verified behaviorally — not byte-identical.

## What this artifact does

`agentic-cms` is a HIPAA-safe multi-agent LLM system that translates
natural-language biomedical research questions into validated SQL
pipelines against CMS Medicaid claims data, paired with the first
public schema-faithful synthetic Medicaid sandbox.

Three contributions to regenerate:

1. **HIPAA-safe agentic governance** — defense-in-depth design,
   server-enforced partition filter, Critic-based static + live
   checks, schema-only data access, statement-timeout-with-`KILL`
   tool layer.
2. **Schema-exact synthetic CMS Medicaid database** — 21 tables,
   2,533 columns, three-era schema crosswalk
   (MAX 2005–2012 / MAX 2013–2015 / TAF 2016+), Synthea-derived TAF
   claims with a Python oncology HCPCS overlay.
3. **End-to-end multi-agent prototype + canonical research pipelines**
   — ReAct loop with Critic retry today (planned 6-node LangGraph
   DAG), 5-stage gold-standard SQL pipelines for diabetes and lung
   cancer, pancreas adapter forthcoming.

## Bootstrap protocol — execute in order

Each step generates one artifact group in the parent directory.
Validate as you go; do not proceed past a failing step without
human input.

1. **Set up the empty target.** If you're not already in an empty
   directory, ask the user where to write the regenerated artifact.
   Default: `../regenerated/` (sibling of `seed/`).
2. **Read [`prompts/01_schema_to_synthetic_db.md`](prompts/01_schema_to_synthetic_db.md).**
   Generate `synthetic_data/` — the schema-faithful synthetic CMS database
   generator. Inputs: [`data/columns_formats.csv`](data/columns_formats.csv).
   Validate: `SKIP_MYSQL=1 bash synthetic_data/build_cms_source.sh`
   produces 21 tables / ~657k rows.
3. **Read [`prompts/02_agent_loop.md`](prompts/02_agent_loop.md).**
   Generate `agents/` — the LLM factory + MySQL tool layer (with
   timeout-and-KILL fallback) + DELIMITER-aware SQL splitter.
4. **Read [`prompts/03_critic_partition_check.md`](prompts/03_critic_partition_check.md).**
   Generate `knowledge/constraints.py`, `knowledge/schema.json`, and
   `knowledge/codes.py` — the rule-based half of the Critic, plus
   schema metadata and disease code-lists.
5. **Read [`prompts/04_skill_cursor_pattern.md`](prompts/04_skill_cursor_pattern.md).**
   Generate `knowledge/skills/extraction_cursor.md` and
   `knowledge/skills/combine_step.md` — the structural skill files
   the agent reads at runtime. (These are themselves prompt-shaped;
   reuse the prompt content nearly verbatim.)
6. **Read [`prompts/05_disease_profile_template.md`](prompts/05_disease_profile_template.md).**
   Generate `knowledge/task_builder.py` and
   `knowledge/diseases/diabetes.py` — the disease-swap mechanism.
7. **Read [`prompts/06_pipeline_5_stages.md`](prompts/06_pipeline_5_stages.md).**
   Generate `pipelines/diabetes/` and `pipelines/lung_cancer/` —
   the 5-stage gold-standard SQL pipelines (claims lane + demographics
   lane, combine, state filter, two-year incident criterion,
   consolidation). Validate: `bash pipelines/diabetes/run_pipeline.sh`
   completes against MySQL with `cms_source` populated.
8. **Read [`prompts/07_phewas_anchor_recipe.md`](prompts/07_phewas_anchor_recipe.md).**
   Generate `cohort_identification/` — the PhecodeX-anchored cohort-
   lookup scaffolding (architecture proposal, MySQL schema for the
   PhecodeX reference DB, loader script, validation-target
   examples). Inputs: [`data/examples/`](data/examples/).
9. **Read [`prompts/08_validation_harness.md`](prompts/08_validation_harness.md).**
   Generate `synthetic_data/tests/`, `toy_db/`, and `tests/` — the
   compliance test suite for the synthetic DB, plus the small MySQL
   fixture and demonstration tests for the agent prototype.
10. **Run `bash seed/verify.sh ../regenerated/`** (or wherever you
    wrote the output). The script will:
    - Run the synthetic DB build.
    - Run `pytest synthetic_data/tests/`.
    - Compare row counts against `evidence/row_counts_v1.json`.
    - Report decompression fidelity (e.g. *"24 of 25 tests passed,
      pipeline row counts within 5% tolerance — fidelity score
      0.96"*).

## Hard rules — never violate

- The agent runs ONLY against synthetic data. Never connect any
  generated agent code to real claims data.
- Every query against `cms_source.*` must include `state_key` AND a
  year filter (`YR_NUM` for MAX, `RFRNC_YR` for TAF). The Critic
  enforces this; do not bypass.
- Identifier-exact regeneration: column names like `DIAG_CD_1..9`,
  `DGNS_CD_1..12`, `RFRNC_YR`, `YR_NUM`, `state_key` (lowercase,
  MAX) vs `STATE_KEY` (uppercase, TAF), `EL_DOB` vs `BIRTH_DT`,
  `SRVC_BGN_DT` / `SRVC_END_DT` (uppercase in both MAX and TAF),
  MUST be preserved exactly as in
  [`data/columns_formats.csv`](data/columns_formats.csv).
- **The CSV is the source of truth for column casing.** When the
  CSV and any prose elsewhere in the seed disagree, the CSV wins.
  Specifically: `gen_data.py` writes row dicts whose keys are
  iterated against `columns_formats.csv`'s column order — dict keys
  with the wrong case become silent NULLs at insert time. This was
  the most common bug discovered in cold-decompression v1
  (see [`EXPERIMENT_v1.md`](EXPERIMENT_v1.md)).
- If you generate code that looks "cleaner" than the spec by
  unifying these inconsistent names, it is wrong. The institutional
  schema is intentionally inconsistent; the agent's job is to track
  the inconsistency, not paper over it.
- License: Apache-2.0. Copyright line: *"Copyright 2026 Shihao Yang
  and contributors"*.
- No PHI, no real beneficiary identifiers, no `.env` files, no
  credentials in any generated file.

## Adapting to a different institution

This seed ships with one institution's schema export
([`data/columns_formats.csv`](data/columns_formats.csv) — 21 tables,
2,533 columns from the original deployment). If you are bootstrapping
this for a *different* institution:

1. Replace [`data/columns_formats.csv`](data/columns_formats.csv) with
   your institution's schema export. The required columns are
   `table_name, column_order, column_name, full_type, is_nullable`.
2. Update [`evidence/row_counts_v1.json`](evidence/row_counts_v1.json)
   to match what your synthetic build produces (or expect
   `verify.sh` to flag differences).
3. The methodology — partition filters, era-aware schema crosswalk,
   cursor pattern — ports unchanged. Your column names are
   different; the structural rules are the same.

If your institutional schema has *more* than three eras, or a
*different* partition rule than `(state, year)`, you will need to
extend [`prompts/03_critic_partition_check.md`](prompts/03_critic_partition_check.md)
and [`prompts/04_skill_cursor_pattern.md`](prompts/04_skill_cursor_pattern.md).
Surface the divergence to the user before generating code.

## Verification semantics

This seed does not promise byte-identical regeneration. Two runs of
the same prompt under the same model produce different code; runs
under different models diverge further. The seed promises **behavioral
equivalence**:

- All 25 compliance tests in `synthetic_data/tests/` pass.
- Row counts at each pipeline stage (Step 1 extraction tables, Step 2
  combine, Step 3 state filter, Step 4 two-year flag) match
  `evidence/row_counts_v1.json` within ±5%.
- The diabetes pipeline produces a non-empty final-cohort table.
- `pytest synthetic_data/tests/` reports `25 passed, 83 subtests
  passed`.

## Failure modes and what to do

- **A prompt is ambiguous.** Stop. Ask the user. Do not invent.
- **A generated file fails its validation step.** Read the error,
  re-read the prompt for what you missed, regenerate that one file.
  Do not proceed to the next prompt with a failing artifact.
- **Compounding errors across prompts.** If three consecutive prompts
  produce broken artifacts, stop and ask the user whether to abort.
- **The user's institutional schema differs in ways the seed
  doesn't anticipate.** Document the divergence, generate the closest
  reasonable approximation, and flag the deviation in a
  `BOOTSTRAP_NOTES.md` at the root of the regenerated artifact.

## File-format conventions you must follow

- All Python files: 4-space indentation, `from __future__ import annotations`
  at the top of every file that uses modern type hints.
- All SQL files: lowercase keywords are fine; the institutional schema
  uses backtick-quoted identifiers; preserve them.
- All Markdown files: GitHub-flavored, no em-dashes if the user has
  configured a no-em-dash skill. Use `—` (en-dash + space) sparingly.
- All shell scripts: `#!/usr/bin/env bash`, `set -eo pipefail`.

## What you should NOT do

- Do not refactor for refactor's sake. The full-repo code is already
  public-grade; reproducing its structure is the goal.
- Do not generate AGENTS.md for the regenerated repo from scratch.
  Copy this file into the regenerated repo's `seed/` if you are
  also reproducing the seed inside the regenerated artifact (a
  "fixed point").
- Do not invent dependencies. The full repo's `pyproject.toml`
  requires only `pytest` + `pytest-subtests` for the headline
  reproducibility path. The agent loop adds `langchain*`,
  `azure-identity`, `python-dotenv`. The MySQL backend adds
  `mysql-connector-python`. Nothing else.
- Do not hallucinate URLs, paper citations, or HCPCS codes.
  Validation targets in [`data/examples/`](data/examples/) are
  the source of truth for code lists.

## When you finish

Write a `BOOTSTRAP_NOTES.md` at the root of the regenerated artifact
documenting:

- Which prompts you ran in what order.
- Which model you used (e.g. `claude-opus-4-7`, `gpt-5`).
- Any prompts you had to re-run after a validation failure.
- Any divergences from the seed's defaults (e.g. *"institution's
  schema has 4 eras instead of 3; extended Critic partition rules
  to cover the new era"*).
- The final `verify.sh` output.

That document is the contribution: not the regenerated code itself,
but the record of what one decompression run looked like.
