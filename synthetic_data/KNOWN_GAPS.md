# Known Gaps — Synthetic CMS Database

Things the current synthetic build **does not** simulate that downstream
pipelines need. Flag for the synthetic-data-generator team as targets for
future `gen_data.py` work. One gap per section; when a gap is closed,
leave the entry and add a "Closed:" line pointing at the commit / PR that
fixed it.

---

## 2. Synthea doesn't model Part B injectable drugs (J/C HCPCS codes)

**Discovered:** 2026-04-22, profiling CMS Synthetic RIF 2023 for Tier 2a loader.

**Symptom.** `SELECT DISTINCT HCPCS_CD FROM rif.carrier` returns **38** codes, all preventive / screening / counseling G-codes. Outpatient has 107 distinct HCPCS, still no oncology / no diabetes-DME. Zero J-codes, zero C-codes for oncology treatment across carrier (1.1 M rows) + outpatient (575 k rows) + DME (100 k rows). The sole J-code anywhere is `J9600` (Levoleucovorin).

**Impact.** Loading RIF directly wouldn't close the original KNOWN_GAPS §1 — lung-cancer treatment arms would still be empty because Synthea's lung-cancer module models the diagnosis but doesn't emit chemo / immuno Part B claims. Same story for diabetes: no J1815 (insulin), no A4253 (test strips), no A5500 series (therapeutic shoes).

**Workaround in place (Tier 2a).** `load_rif.py` runs a Python HCPCS overlay after loading RIF: for each Synthea-flagged lung-cancer beneficiary, appends 6-24 synthetic `taf_other_services_line` rows with J/C codes drawn from `HCPCS_CHEMO` / `HCPCS_IMMUNO` pools. Preserves RIF realism for diagnoses / demographics / NDC prescriptions; adds the treatment signal Synthea doesn't emit. This is explicitly flagged as overlay (CLM_ID prefix `ONCO`) so anyone downstream can tell synthetic-overlay rows from real-RIF rows.

**Real fix (Tier 3).** Run Synthea locally with a custom oncology module + RIF exporter that emits Part B J/C codes for treated cancer patients. Would also give us Medicaid TAF (which Synthea doesn't currently export; this is the citable methodology extension noted in CLAUDE.md).

---

## 1. `taf_other_services_line.LINE_PRCDR_CD` is a single placeholder value — CLOSED

**Closed:** 2026-04-22 in commit `<phase-F>` via `gen_data.py` changes — `pick_treatment_type` patient-level sampler + `pick_line_hcpcs` per-row draw + four new HCPCS pools (`HCPCS_CHEMO`, `HCPCS_IMMUNO`, `HCPCS_DIAB`, `HCPCS_GENERIC`) sourced from the lung-cancer and diabetes gold-standard reference tables. After regeneration:

- `taf_other_services_line` has **59 distinct `LINE_PRCDR_CD` values** (up from 1) — 12 chemo J-codes, 12 immuno J+C-codes, 16 diabetes management codes, 19 generic E/M + lab codes.
- 5,609 chemo HCPCS rows + 4,574 immuno HCPCS rows across 104,602 total line rows, giving the lung-cancer pipeline meaningful treatment-arm signal.
- The full lung-cancer survival pipeline now produces non-zero output at every stage: `chemo_table_final` (4), `immuno_table_final` (9), all 6 per-drug subgroup tables populated, all 4 per-disease subgroups populated.
- `taf_inpatient_line.LINE_SRVC_BGN_DT / _END_DT` also fixed (were '0000-00-00' sentinels that tripped NO_ZERO_DATE).

`entry preserved below for traceability.`

---

**Discovered:** 2026-04-21, running the lung-cancer gold-standard Step 1 pipeline (`pipelines/lung_cancer/run_step1.sh`) against `cms_source`.

**Symptom.** `SELECT COUNT(DISTINCT LINE_PRCDR_CD) FROM cms_source.taf_other_services_line` returns **1** across 104,448 rows. Zero J-codes, zero C-codes, zero meaningful HCPCS diversity. The lung-cancer step 1 procedures `chemo_ospatient_records` and `immuno_ospatient_records` consequently produce **0 rows** — not because the SQL is wrong (it isn't; the same SQL runs correctly), but because there's nothing to match against.

**Impact.** Any pipeline whose cohort definition depends on procedure/treatment codes is unreproducible on the current synthetic build. That includes:
- **Lung cancer + immunotherapy adverse-event study** — chemo and immuno exposure arms are empty, so steps 2–5 (merge, v3/v4/v6/v7, final survival tables) can't be validated end-to-end.
- **Any future oncology study** using HCPCS J-codes or pre-approval C-codes.
- **Any diabetes-treatment study** using HCPCS insulin / glucose-monitoring / DME codes (J1815, A4253, A4259, A5500…). The current diabetes gold-standard pipeline is diagnosis-driven only, so this gap isn't visible there yet, but it would matter if the pipeline were extended to treatment-arm analysis.

**Root cause.** `gen_data.py` seeds `LINE_PRCDR_CD` with a single placeholder because the cohort-bucket design (positive / single / long_gap / wrong_state / no_diabetes / ambiguous) is diagnosis-focused — it was tuned to exercise the diabetes Step 3–5 filtering logic. Procedure-code diversity wasn't in scope for the initial build.

**What a fix looks like.** When `gen_data.py` is extended for oncology or treatment-arm support, seed `LINE_PRCDR_CD` from a realistic HCPCS distribution. The reference lists already exist:

- Oncology chemo J-codes — [`pipelines/lung_cancer/reference/build_reference_tables.sql`](../pipelines/lung_cancer/reference/build_reference_tables.sql) (12 J-codes: J9060, J9045, J9267, J9264, J9171, J9201, J9305, J9390, J9181, J9206, J9035, J9308).
- Oncology immuno J-codes + C-codes — same file (12 codes: J9228, J9299, J9271, J9022, J9173, J9023, C9027, C9284, C9453, C9483, C9491, C9492).
- Diabetes HCPCS — [`pipelines/diabetes/reference/hcpcs_code.sql`](../pipelines/diabetes/reference/hcpcs_code.sql) (58 codes: J1815, J1817–J1819, A4253, A4259, A9274–A9288, A5500–A5512, E0780–E0784, G0108–G0109, etc.).
- Full HCPCS quarterly release — [`cohort_identification/databases/hcpcs/`](../cohort_identification/databases/hcpcs/).

Minimum-viable fix: enrich the existing cohort buckets with a "has_oncology_treatment" flag (10%?) and a "has_diabetes_treatment" flag (40% of `positive`?), and draw `LINE_PRCDR_CD` from the appropriate HCPCS list when the flag is set. Non-treatment claims keep the placeholder.

Medium-term: model the TAF line-level structure more faithfully — `LINE_PRCDR_CD_DT`, `LINE_PRCDR_MDFR_CD_1..4`, `LINE_SRVC_BGN_DT` / `END_DT` realistic distributions, line-level `CLM_ID` joining back to the header. Currently the line table exists but the per-claim procedure distribution isn't realistic.

**Tests to add alongside the fix.** Once LINE_PRCDR_CD is diverse:
- `taf_other_services_line` has at least 50 distinct `LINE_PRCDR_CD` values.
- A non-trivial fraction of positive-cohort patients have at least one chemo or immuno HCPCS in their claim history (for oncology synthetic slices).
- A non-trivial fraction of diabetes-positive patients have at least one insulin / glucose-monitoring HCPCS.

