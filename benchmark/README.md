# MedSQL-CMS Benchmark — Forthcoming

A reviewer-credible benchmark for evaluating natural-language → SQL
agents on CMS Medicaid claims is one of the proposal's deliverables.
This folder will hold the benchmark pairs (prompt + expected SQL +
expected output rowset) once the grant work is underway.

## Plan

- **150+ pairs**, scoped to the diabetes, lung-cancer, and pancreas
  cohort recipes (plus per-disease-subgroup variants).
- **Cross-model evaluation** at two cost tiers (GPT-4o-class vs.
  GPT-4o-mini-class) with retry budgets reported.
- **Validation against the synthetic CMS sandbox in
  [`../synthetic_data/`](../synthetic_data/)** — every benchmark
  query must produce a non-empty result against the synthetic DB
  before being added to the corpus.
- **Per-pair difficulty rating** capturing the era-aware schema
  challenge (single era vs. cross-era UNION) and the cohort-rule
  complexity (single-claim filter vs. 24-month cursor-based
  incident-criterion).

## Pointers

- The proposal aim that funds this benchmark — see the top-level
  `README.md` "Status" section.
- The current evaluation surface — manual end-to-end runs in
  [`../tests/`](../tests/) with saved traces.

[`pairs/`](pairs/) is intentionally empty for now; a `pair_xxx.json`
or `pair_xxx.yaml` schema will be defined when the first pairs land.
