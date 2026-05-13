# HIPAA Model

The agent runs only against synthetic data. Real CMS Medicaid claims
data lives behind an institutional HIPAA enclave and is accessed only
through a credentialed human reviewer. This document spells out the
trust boundary, what's currently codified, and the gaps the proposal
calls out as future Aims.

## Trust boundary — three zones, two crossings

**Zone 1 (public, this repository).** The multi-agent prototype, the
schema-faithful synthetic CMS database, public reference databases
(PhecodeX, ICD, HCPCS, NDC, CCSR), and the agent's LLM API calls. **No
PHI ever lives here, by construction.**

**Zone 2 (institutional HIPAA enclave, NOT in this repository).** The
real Medicaid claims MySQL warehouse, accessed via VPN → 2FA →
institutional VDI → MySQL Workbench.

**Zone 3 (the credentialed human reviewer).** The only carrier of
information across the boundary in either direction.

```
   ┌──────────────────┐                            ┌──────────────────┐
   │ Zone 1 — public  │                            │ Zone 2 — HIPAA   │
   │                  │                            │ enclave (real    │
   │ • agent          │ ──── schema metadata ────► │   PHI)           │
   │ • synthetic DB   │      (col names/types)     │                  │
   │ • PhecodeX/ICD   │      ◄── aggregate ──────  │ • VPN + 2FA + VDI│
   │ • LLM API        │      result tables         │ • MySQL Workbench│
   │                  │                            │                  │
   │       ─── vetted SQL text crosses INBOUND ───►│                  │
   │       ◄── aggregate result tables crosses OUT │                  │
   └──────────────────┘                            └──────────────────┘
                  ▲                                  ▲
                  │                                  │
                  └── credentialed human reviewer ───┘
```

The two crossings:

1. **Outbound from the enclave:** schema export
   ([`synthetic_data/columns_formats.csv`](../synthetic_data/columns_formats.csv) —
   column metadata only, no rows) plus aggregate result tables that
   the human reviewer brings out under institutional cell-suppression
   rules.
2. **Inbound to the enclave:** human-reviewed SQL text. The agent has
   zero direct network connection.

## What the agent sees vs. what it must not

| Sees | Must not see |
|---|---|
| `knowledge/schema.json` (column metadata only) | Any row of real Medicaid claims |
| `synthetic_data/columns_formats.csv` (institutional column names + types) | Real beneficiary identifiers, names, addresses |
| The synthetic CMS database (`cms_source`) | Outputs of real-CMS pipeline runs |
| Public ICD/HCPCS/NDC reference databases | `.env`, `*.pem`, `*.key`, VPN tokens |
| Skill files in `knowledge/skills/` | |

These are codified in `.gitignore` and in the synthetic-data folder's
own scope rule: *"No HIPAA data ever reaches this folder. All inputs
are public synthetic datasets; all outputs are generator-produced."*

## Defense in depth — concrete, codified

Layered checks that any agent-emitted SQL must survive before it can
run against real claims data:

1. **Database-level partition filter (server-enforced).** Every query
   against a `cms_source` source table must include a `state_key` /
   `STATE_KEY` filter AND a year filter (`YR_NUM` for MAX era,
   `RFRNC_YR` for TAF era). The institutional production server
   auto-kills unpartitioned scans. See
   [`knowledge/constraints.py`](../knowledge/constraints.py) lines
   15–26 for the rule the Critic enforces statically before a query
   ever hits the wire.

2. **Critic node — static check.** Two text-search functions in
   [`knowledge/constraints.py`](../knowledge/constraints.py):
   `check_partition_filter()` flags missing `state_key` / year filters,
   and `check_column_names()` flags era-mismatched identifiers (e.g.
   `DIAG_CD_*` against a TAF table that uses `DGNS_CD_*`). The agent
   loop retries up to 3 times on failures.

3. **Critic node — live check.** Post-execution `SELECT COUNT(*) FROM
   <output_table>` must return > 0. Empty outputs commonly indicate a
   silently-wrong filter (case-sensitive column-name mistake,
   wrong-era diagnosis-code prefix, etc.).

4. **Cursor-based partition iteration.** The skill files
   ([`knowledge/skills/extraction_cursor.md`](../knowledge/skills/extraction_cursor.md))
   require a stored-procedure cursor over
   `state_codes × data_years`, so the agent cannot accidentally
   request a full-table scan.

5. **Statement timeout in the tool layer.** The `execute_sql` tool
   ([`agents/tools/mysql_tools.py`](../agents/tools/mysql_tools.py))
   runs each statement on a dedicated connection in a daemon thread
   with a 30-second timeout. On hang, the tool issues
   `KILL QUERY <connection_id>` from a separate connection so the
   worker thread can exit cleanly without blocking the agent loop.

6. **Era-correct partition indexes in the synthetic schema.**
   [`synthetic_data/gen_ddl.py`](../synthetic_data/gen_ddl.py) emits
   `(state_key, YR_NUM)` and `(STATE_KEY, RFRNC_YR)` indexes that
   mirror the institutional production index structure, so query
   planning behaves the same on synthetic vs. real.

7. **VPN + 2FA + VDI + domain auth** before the institutional database
   is even reachable. Out of scope for this repo; documented for
   completeness.

8. **Repo hygiene.** [`.gitignore`](../.gitignore) blocks `.env`,
   `*.pem`, `*.key`, `real_data/`, `phi/`, `real_cms_outputs/`,
   `production_results/`. Cohort-identification reference databases
   are gitignored too because they're large and publicly
   redownloadable, not because they're sensitive — but the same
   default-deny posture applies.

## Honest gaps — what the proposal calls out as future Aims

The codified controls above cover the *technical* boundary. The
*governance* boundary needs more work, and the proposal is explicit
about it:

1. **No IRB protocol number** is cited in the codebase. The
   institutional protocol exists; the codified pointer to it does
   not.
2. **No NIST 800-53 / HIPAA Security Rule control map** in the
   codebase. The defense-in-depth list above is informal; mapping
   each layer to a named control is the work.
3. **No formal human-reviewer checklist or sign-off form.** The
   principle ("a credentialed human reviews every query before it
   runs against real data") is stated but the workflow is not
   hardened — no signed sign-off, no audit log of who-vetted-what.
4. **No cell-suppression / k-anonymity / minimum-cell-count layer
   on agent-emitted outputs.** The CMS Cell Size Suppression Policy
   (counts < 11 redacted) is a real research contribution that
   would need to be codified before the agent could safely emit
   non-aggregate outputs.

These four gaps **are the proposal's safety-and-governance Aim**: a
written architecture-and-controls document mapped to NIST 800-53 /
HIPAA Security Rule, a codified human-review workflow with audit
logs, and an output-side cell-suppression / DP layer.

## What's required of you (the maintainer)

If you are deploying or extending this agent on top of a real
HIPAA-regulated database:

- Get IRB approval for your protocol; cite the protocol number in
  your fork's `docs/hipaa.md`.
- Codify a human-reviewer sign-off workflow appropriate to your
  institution.
- Implement an output-side suppression layer (cell counts < 11
  redacted) for any agent-generated aggregates that leave the
  enclave.
- Never connect the agent code (anything under
  [`agents/`](../agents/) or [`tests/`](../tests/)) to a network
  path that can reach real PHI. Run the agent only against
  [`synthetic_data/`](../synthetic_data/) or an equivalent fully
  synthetic / de-identified fixture.
