# EXPERIMENT v1 — Cold-Decompression Trial

## What happened

A fresh AI coding agent was given access only to `seed/` (this folder)
and was asked to regenerate the full `agentic-cms` artifact into an
empty target directory `/tmp/agentic-cms-regen/`. It was explicitly
forbidden from reading the canonical implementations.

**Model:** Claude Sonnet (general-purpose subagent).
**Wall time:** ~45 minutes / 149 tool uses / 239k tokens.
**Date:** 2026-05-10.

## Headline number

**`verify.sh` reported 31/31 PASS (fidelity = 1.00) with 2 WARN.**

The agent regenerated every required file, the synthetic-DB build
succeeded, and `pytest synthetic_data/tests/` reported 25/25 named
tests passed.

However, the headline 1.00 is **misleading**:

- Only **6 of 21 row-count tables** were within ±5% tolerance — most
  were 33–77% off canonical.
- The SHA-256 of the regenerated `synthetic_db.sqlite` differed from
  the canonical run.
- The subtest count was 77, not the 83 the seed promised.

These all logged as `[WARN]`, not `[FAIL]`, in v1's `verify.sh`. The
PASS/FAIL universe was dominated by structural file-existence checks
(28 of 31), so a structurally-complete-but-quantitatively-wrong
regeneration scored the same as a faithful one. **The verify metric
is too generous in v1.**

## Per-prompt outcome

| # | Prompt | Regenerated | Passes own validation? |
|---|---|---|---|
| 01 | schema_to_synthetic_db | yes | yes (build runs, pytest 25/25), row counts ~40% of canonical |
| 02 | agent_loop | yes | not exercised (no MySQL/Azure in sandbox) |
| 03 | critic_partition_check | yes | not exercised |
| 04 | skill_cursor_pattern | yes | yes (text files) |
| 05 | disease_profile_template | yes | not exercised |
| 06 | pipeline_5_stages | partial | diabetes faithful; lung_cancer Step 5 truncated to 1 of ~30 subgroup unions |
| 07 | phewas_anchor_recipe | yes | yes (structural) |
| 08 | validation_harness | yes | pytest 25 passed; 77 subtests not 83 |

## Concrete bugs the cold agent identified

These are the actionable output of the experiment — patches applied
in v2 (commit history records this).

### Bug 1: `SRVC_BGN_DT` casing inconsistency [FIXED v2]

- Prompts 01 / 03 / 04 used lowercase `srvc_bgn_dt`.
- `seed/data/columns_formats.csv` has uppercase `SRVC_BGN_DT`,
  `SRVC_END_DT` for both MAX and TAF tables.
- Cold agent shipped lowercase, debugged ~5 minutes after rows came
  out null (`row.get("srvc_bgn_dt")` returns None when the CSV-
  derived column iteration uses uppercase keys).
- **Fix:** prompts now use uppercase consistently; AGENTS.md adds an
  explicit "the CSV is the source of truth for column casing" rule.

### Bug 2: `long_gap` bucket doesn't bound second claim to era window [FIXED v2]

- Prompt 01 said "long_gap: 2 claims, 731–900 days apart" without
  bounding the second claim to the era's year window.
- Naive implementation lets an ERA1 (2005–2012) patient's second
  claim land in 2014, breaking `test_year_ranges_match_era`.
- **Fix:** prompt 01 now says "both claims must remain inside the
  era's year window" with a clamp pattern shown.

### Bug 3: Inpatient-vs-outpatient track ratio unspecified [FIXED v2]

- Canonical `other_therapy = 59,205 > inpatient = 43,209` (outpatient
  larger because of the "always-outpatient-if-no-inpatient" fallback).
- Prompt 01 didn't document this ratio; cold agent's outpatient was
  ~37% of canonical.
- **Fix:** prompt 01 now includes a canonical per-table row-count
  table and documents the `show_inp / show_out / show_rx` draw rule.

### Bug 4: 83-subtests breakdown not enumerated [FIXED v2]

- Prompt 08 said "25 tests / 83 subtests" without showing where
  the 83 break down per test.
- Cold agent produced 77; undiagnosable from the seed.
- **Fix:** prompt 08 now has a per-test subtest-count table
  (21 + 21 + 3 + 3 + 6 + 7 + 9 + 4 + 9 = 83).

### Bug 5: Prompt 06 under-specified for `pipelines/lung_cancer/` [FIXED v2]

- Prompt 06 was the longest but treated lung_cancer as "similar
  shape to diabetes."
- Cold agent shipped diabetes faithfully but truncated lung-cancer
  Step 5 from ~30 per-drug/per-disease subgroup unions to 1
  (NI+T1 only).
- **Fix:** prompt 06 now has a "more complex than diabetes"
  callout, concrete SQL templates for per-drug and per-disease
  subgroups, and the explicit count of ~30 subgroup tables to
  generate.

## Surprising discoveries

1. **The verify metric is gameable.** An agent producing
   correctly-named stubs + a trivial-but-passing test suite scores
   1.00. The structural file checks dominate the PASS/FAIL universe.
   Future v2+ should weight row-count fidelity and SHA-256 match
   into the headline score.

2. **MySQL/SQLite case-insensitivity hid the casing bug locally.**
   The canonical `knowledge/schema.json` and `knowledge/constraints.py`
   actually use lowercase `srvc_bgn_dt` — they work coincidentally
   because the database engine normalizes case in WHERE clauses. The
   cold agent's failure was specifically in the **Python dict-key
   iteration** path (`row.get("srvc_bgn_dt")` is case-sensitive in
   Python, unlike SQL).

3. **The 2,533 column-count assertion is the strongest fixed point**
   in the seed. Every test referencing it and the CSV both align;
   the cold agent never had ambiguity on this.

4. **`DE-SynPUF` preflight as a hidden conditional.** The cold agent
   shipped a stub `DE1_0_2008_Beneficiary_Summary_File_Sample_1.csv`
   to trigger the build path. In v2, AGENTS.md should clarify that
   the preflight is intentional and that running with a stub CSV is
   acceptable for measurement.

## What worked well — keep these

- **Prompt 02 (agent_loop):** "the threading+KILL pattern is
  unusually well-specified; no changes needed."
- **Prompts 04 (skill files), 07 (PheWAS recipe):** "Good as-is."
- **The 2,533 column count** as a hard assertion threaded through
  CSV, gen_ddl, and test_synthetic_db.
- **The "behavioral pass, not byte-equality" framing** in
  AGENTS.md — the cold agent correctly trusted this and didn't
  waste effort chasing byte-equality.

## Compression numbers (re-measured)

| Layer | v1 size | Notes |
|---|---|---|
| prompts/ + AGENTS.md | 88 KB | The actual information |
| Regenerable code | 748 KB | What v1 produced |
| Ratio (method layer) | **8.5×** | |
| Total seed footprint | 380 KB | Incl. irreducible data/evidence |

v2 will grow the prompts slightly (estimated +15 KB after the 5
fixes) for a final compression ratio around **7.5×** — slightly
worse on paper, much better on first-pass decompression fidelity.

## What v2 should do (open questions for the next experiment)

1. **Tighten `verify.sh`.** Make row-count fidelity contribute to
   the headline score (e.g. `weighted_fidelity = 0.5 * structural +
   0.3 * row_counts + 0.2 * pytest_pass`). Re-run cold agent.
2. **Run a second cold trial under a different model.** v1 used
   Claude Sonnet; trying GPT-5 or Claude Opus would measure
   cross-model decompression robustness.
3. **Measure the lung-cancer subgroup completeness explicitly.**
   Add `verify.sh` checks counting the actual number of per-drug /
   per-disease tables in `pipelines/lung_cancer/step5_consolidate/`.
4. **Iteration to convergence.** Have the cold agent run its own
   verify.sh and self-correct based on the warnings. v1 didn't
   close this loop; the agent regenerated, ran verify once,
   reported, and stopped.

## Files at the time of v1

Cold-agent's regenerated artifact is at `/tmp/agentic-cms-regen/`.
Full transcript / per-tool-use trace is preserved internally as
sub-agent task `a755f091438806c31` (2026-05-10).

---

**Status:** v1 results documented. v2 seed prompts patched. v2
cold-decompression trial pending.
