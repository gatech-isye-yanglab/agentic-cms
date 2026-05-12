# Lung Cancer + Autoimmune Side-Effect Pipeline — Gold-Standard SQL

A reproducible CMS Medicaid claims pipeline for an
**immunotherapy-induced autoimmune adverse-event** study in lung cancer.
Identifies a lung-cancer cohort, separates them into chemotherapy and
immunotherapy exposure arms, attaches autoimmune outcomes, and produces
final survival-analysis tables with per-drug and per-disease breakdowns.

This pipeline is the **cross-disease generalisation test** for the
multi-agent prototype: same CMS schema as the diabetes case, different
ICD codes and filtering logic, more complex exposure / outcome modelling.

**Headline endpoint:** Cox hazard ratios for autoimmune events under
checkpoint-inhibitor therapy versus chemotherapy, with per-drug HRs
(nivolumab, pembrolizumab, atezolizumab, ipilimumab) and per-disease HRs
(diabetes mellitus, hypothyroidism, thyroiditis, myalgia, rheumatoid
arthritis).

**Cohort scope:** Three parallel CMS schema eras reconciled into one
analytical dataset — MAX 2005–2015, TAF 2016, TAF 2017+. The final
survival-analysis tables UNION the 2017+ pipeline with the 2016-era
pipeline.

---

## A note on "gold standard with noise"

This folder is a **gold standard with noise** — deliberately so.

The SQL under `step1_extraction/` … `step5_consolidate/` is the canonical
pipeline that produced published survival results for an autoimmune-events
analysis in lung-cancer immunotherapy. It is structurally complete and
runs end-to-end. That's the "gold standard" part.

The "noise" part is intentional and has two sources:

1. **The institutional reference tables were purged from the production
   server.** The four code-list tables the stored procedures read from
   (`ICD910_lung_cancer_codes`, `autoimmune_icd`, `immuno_cpt_codes`,
   `chemo_cpt_codes`) are no longer on the live VM. So
   [`reference/`](reference/) contains *recovered benchmarks* derived
   from a public PheWAS-anchor recipe (see
   [`../../cohort_identification/architecture_proposal.md`](../../cohort_identification/architecture_proposal.md))
   plus the inline ICD list embedded in the gold-standard MAX-era SQL.
   These are close to, but not byte-identical with, the original
   institutional reference tables.

2. **Row-count ground truth is pending.** Authoritative `n` at each
   v3/v4/v6/v7 stage and the final-table row counts are not yet
   committed. Until they are, "does the SQL match" is the only check;
   "does it produce the same numbers on the institutional database" is
   future work.

**Why ship it with noise rather than wait?** The SQL is the **structural
template** — the institutional, identifier-exact shape that an agent
should learn to reproduce. The synthetic CMS sandbox in
[`../../synthetic_data/`](../../synthetic_data/) is the corresponding
reproducible target. Once the cell-counts ground truth lands, this folder
will validate end-to-end on synthetic data with no remaining noise.

---

## Architecture

```
                 EXPOSURE LANE                OUTCOME LANE
                 ─────────────                ────────────
Step 1   lung_cohort_MAX,                 outcome_autoimmune_TAF
         lung_cohort_MAX1315,             (autoimmune dx 2016+
         lung_cohort_TAF                   inpatient + outpatient)
         (lung-cancer dx 2005-2015,            │
          2017+ TAF)                           │
            │                                  │
            ↓                                  │
         exposure_chemo_immuno_TAF             │
         (chemo / immuno HCPCS,                │
          2017+ TAF)                           │
            │                                  │
Step 2      ↓                                  ↓
         per_patient_summary tables (single-row-table per patient,
         per cohort + exposure + outcome arm)
            │
Step 3      ↓
         cohort_x_exposure_x_outcome
         (joined per-patient table)
            │
Step 4      ↓
         demographics_and_inclusion
         (BIRTH_DT, SEX, RACE attached;
          inclusion criteria applied;
          v3/v4/v6/v7 staged outputs)
            │
Step 5      ↓
         final_tables
         (Cox-ready survival tables:
          per-drug + per-disease subgroups,
          UNION of TAF-2017+ and TAF-2016)
```

---

## Execution order

### Step 1 — Reference tables (run first)

| File | Purpose |
|---|---|
| [`reference/build_reference_tables.sql`](reference/build_reference_tables.sql) | Builds 4 code-list tables (lung-cancer ICD, autoimmune ICD, chemo HCPCS, immuno HCPCS) from PhecodeX + the inline gold-standard ICD list. |
| [`reference/autoimmune_sub_slices.sql`](reference/autoimmune_sub_slices.sql) | Sub-slice tables for the per-disease autoimmune subgroup analysis (T1 diabetes, hypothyroidism, thyroiditis, RA, etc.). |

The four `*_legacy_claims.md` files in [`reference/`](reference/) are
**provenance documentation** for the recovered code lists — they cite
the published-paper code lists the recovered benchmarks were derived
from. They are not consumed at runtime.

### Step 2 — Step-1 extraction (run all 5)

| File | Purpose |
|---|---|
| [`step1_extraction/lung_cohort_MAX.sql`](step1_extraction/lung_cohort_MAX.sql) | Lung-cancer cohort 2005–2012 (MAX era). |
| [`step1_extraction/lung_cohort_MAX1315.sql`](step1_extraction/lung_cohort_MAX1315.sql) | Lung-cancer cohort 2013–2015 (MAX era). |
| [`step1_extraction/lung_cohort_TAF.sql`](step1_extraction/lung_cohort_TAF.sql) | Lung-cancer cohort 2017+ (TAF era). 2016 is handled by a separate parallel pipeline that catches pre-approval C-codes via regex; once both are populated, Step 5 unions them. |
| [`step1_extraction/exposure_chemo_immuno_TAF.sql`](step1_extraction/exposure_chemo_immuno_TAF.sql) | Chemo + immunotherapy HCPCS exposure tables (2017+ TAF). |
| [`step1_extraction/outcome_autoimmune_TAF.sql`](step1_extraction/outcome_autoimmune_TAF.sql) | Autoimmune outcome tables (inpatient + outpatient, 2016+). |

A bonus convenience runner — [`run_step1.sh`](run_step1.sh) — runs just
this step.

### Step 3 — Per-patient summary

[`step2_per_patient_summary/srt_tables.sql`](step2_per_patient_summary/srt_tables.sql)
collapses each step-1 output into a single-row-per-patient table for
downstream joins.

### Step 4 — Merge cohort × exposure × outcome

[`step3_merge/cohort_x_exposure_x_outcome.sql`](step3_merge/cohort_x_exposure_x_outcome.sql)
joins the lung-cancer cohort with each exposure arm and each outcome arm.

### Step 5 — Demographics + inclusion criteria

- [`step4_demographics_and_criteria/inclusion_and_covariates.sql`](step4_demographics_and_criteria/inclusion_and_covariates.sql) — applies inclusion criteria (age, study window) and stages outputs as `v3 → v4 → v6 → v7`.
- [`step4_demographics_and_criteria/prep_entire_records_and_covariates.sql`](step4_demographics_and_criteria/prep_entire_records_and_covariates.sql) — backfills 2016-era dates from the parallel TAF-2016 pipeline.

### Step 6 — Final survival-analysis tables

[`step5_consolidate/final_tables.sql`](step5_consolidate/final_tables.sql)
emits Cox-ready survival tables:
- Overall: `chemo_table_final`, `immuno_table_final`.
- Per drug: nivolumab (NI), pembrolizumab (PE), atezolizumab (AT),
  durvalumab (DI), avelumab (AV), ipilimumab (IP).
- Per disease: T1 diabetes, hypothyroidism, RA, thyroiditis, myalgia.

Each per-drug / per-disease table UNIONs the TAF-2017+ pipeline with the
TAF-2016 parallel pipeline so the analytical row count is one per
patient across the full 2016+ window.

---

## Running it

```bash
# End-to-end pipeline:
bash run_pipeline.sh

# Step 1 only (for fast iteration on the cohort definition):
bash run_step1.sh
```

Same prerequisites as the diabetes pipeline — see
[`../diabetes/README.md`](../diabetes/README.md#running-it).

---

## Status

- [x] Step-1 extraction SQL (5 files)
- [x] Per-patient summary, merge, demographics, final-tables SQL
- [x] Reference table builder (recovered from PhecodeX + inline ICD list)
- [x] Provenance documentation for the recovered benchmarks (`reference/*_legacy_claims.md`)
- [ ] End-to-end run on the synthetic CMS sandbox produces non-zero rows
      at every stage (oncology HCPCS overlay in `synthetic_data/load_rif.py`
      addresses the empty-LINE_PRCDR_CD problem; some downstream tables
      are still small because Synthea generates ~25 lung-cancer cases —
      see [`../../synthetic_data/KNOWN_GAPS.md`](../../synthetic_data/KNOWN_GAPS.md))
- [ ] Authoritative row-count ground-truth from the institutional run
      committed alongside this pipeline
