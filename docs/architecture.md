# Architecture

This document is a public-facing tour of the system: how the pieces
fit together, what crosses which boundary, and what the agent does
versus what the human does.

## One-paragraph picture

A natural-language biomedical research question (e.g. *"identify
incident diabetes patients in seven southeast US states with at
least two qualifying claims within 24 months"*) flows into a
multi-agent prototype that drafts the corresponding CMS Medicaid SQL
pipeline. The agent runs only against a schema-exact synthetic CMS
sandbox; a credentialed human reviewer is the only path that crosses
into the real institutional Medicaid database. The synthetic sandbox
mirrors the real schema's column names, partition rules, and era
distinctions byte-for-byte, so SQL that passes against synthetic
either passes against real data or fails for a non-schema reason.

## Two parallel data planes

```
                     ┌──────────────────────────────────────────────┐
                     │   PUBLIC PLANE  (this repository)            │
                     │                                              │
   user prompt ──►   │   Multi-agent prototype                      │
                     │   ─────────────────────                      │
                     │   Azure GPT-4o ReAct loop                    │
                     │     • execute_sql tool (30s timeout + KILL)  │
                     │     • preview_table tool (schema only)       │
                     │     • Critic: partition-filter check         │
                     │   Knowledge layer                            │
                     │     • schema.json (column metadata, no rows) │
                     │     • constraints.py (Critic checks)         │
                     │     • skills/* (cursor / combine patterns)   │
                     │     • diseases/* (per-disease profiles)      │
                     │   Synthetic sandbox                          │
                     │     • cms_source MySQL/SQLite                │
                     │     • 21 tables × 2,533 columns              │
                     │     • Synthea-derived TAF claims +           │
                     │       Python-generated MAX claims +          │
                     │       oncology HCPCS overlay                 │
                     │   Public reference data                      │
                     │     • PhecodeX, ICD-9/10, GEMs,              │
                     │       HCPCS, NDC, AHRQ CCSR                  │
                     │                                              │
                     │   ─── output ────►   vetted SQL text         │
                     └──────────────────────────────────────────────┘
                                            │
                                            │  human reviewer carries
                                            │  vetted SQL across the
                                            │  trust boundary
                                            ▼
                     ┌──────────────────────────────────────────────┐
                     │   INSTITUTIONAL HIPAA PLANE  (NOT this repo) │
                     │                                              │
                     │   VPN + 2FA + VDI + MySQL Workbench          │
                     │   Real CMS Medicaid claims (PHI)             │
                     │   Aggregate result tables come back out      │
                     │   under cell-suppression rules               │
                     └──────────────────────────────────────────────┘
```

The agent has **zero network connection** to the institutional
database. The two crossings are both human-mediated:

1. **Outbound from the institution:** schema metadata
   (`columns_formats.csv`, column names + types only — never row data)
   plus aggregate result tables vetted by a credentialed researcher.
2. **Inbound to the institution:** human-reviewed SQL text.

## The agent loop today

```
                      ┌─────────────────┐
                      │   User prompt   │
                      └────────┬────────┘
                               │
                               ▼
                ┌──────────────────────────┐
                │  Task builder            │
                │  (knowledge/task_builder │
                │   + diseases/<X>.py +    │
                │   skills/*.md)           │
                └────────┬─────────────────┘
                         │
                         ▼
                ┌──────────────────────────┐
                │  SQL Writer (ReAct loop) │ ◄────────┐
                │   • execute_sql          │          │
                │   • preview_table        │          │
                └────────┬─────────────────┘          │
                         │                            │
                         ▼                            │
                ┌──────────────────────────┐          │
                │  Critic                  │          │
                │   • partition-filter chk │ feedback │
                │   • column-name check    │ on fail  │
                │   • output-rows > 0      │──────────┘
                └────────┬─────────────────┘
                         │ on pass
                         ▼
                  generated SQL
```

The Critic runs **static** (regex-based partition-filter and
column-name checks against the SQL text, before it touches the DB)
and **live** (`SELECT COUNT(*) FROM <output>` after execution must be
positive). On failure the Critic writes feedback and routes back to
the SQL Writer, up to 3 retry rounds.

## Planned 6-node DAG

The architecture this current MVP builds toward is a LangGraph DAG
with separate nodes for each responsibility:

```
   Orchestrator ──► Schema ──► Clinical ──► SQL Writer ──► Critic ──► Assembler
                                                ▲              │
                                                └── retry ─────┘
```

- **Orchestrator** parses the user prompt into a task spec.
- **Schema Agent** picks the right tables and column names per era.
- **Clinical Agent** translates the disease into ICD/HCPCS/NDC code
  sets via the
  [cohort_identification](../cohort_identification/) lookup recipe.
- **SQL Writer** drafts the cursor-pattern SQL using the skill files.
- **Critic** runs the partition / column / output-row checks.
- **Assembler** stitches per-step SQL into a multi-step pipeline.

In today's MVP, the Schema Agent / Clinical Agent / Assembler
responsibilities are inlined into the SQL Writer's system prompt
rather than separate nodes. Splitting them out is the planned grant
work.

## What the agent never sees

- Real beneficiary identifiers, dates, diagnosis codes from PHI
- Outputs of any real-CMS pipeline run
- Any `.env`, credentials, or VPN tokens (`.gitignore` enforced)

## What the agent does see

- `knowledge/schema.json` — column metadata only, no rows
- `synthetic_data/columns_formats.csv` — institutional schema export
  (column names + types, never data)
- The synthetic CMS database itself
- Public reference databases (PhecodeX, ICD-9/10, HCPCS, NDC, CCSR)
- Skill files in `knowledge/skills/`
- The legacy gold-standard SQL in `pipelines/`

## Pointers

- HIPAA model and defense-in-depth detail: [docs/hipaa.md](hipaa.md)
- Synthetic database design: [docs/synthetic_data.md](synthetic_data.md)
- Cohort-identification recipe: [cohort_identification/architecture_proposal.md](../cohort_identification/architecture_proposal.md)
- Current agent code: [agents/README.md](../agents/README.md)
- Demonstration tests + saved traces: [tests/README.md](../tests/README.md)
