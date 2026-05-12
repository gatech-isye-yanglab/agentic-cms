Step 1 — Extraction
===================

Three parallel extractions produce the raw materials for the lung-cancer +
autoimmune study. Each is disease-specific on the reference table it joins
against and otherwise the same cursor-over-(state × year) pattern the
diabetes pipeline uses.

| File | Produces | Reads | ICD/HCPCS source |
|---|---|---|---|
| `lung_cohort_MAX.sql` | lung-cancer patient counts (2005-2015) | `cms_source.inpatient` (MAX era) | Inline ICD list (the MAX-era pipeline, authoritative) |
| `lung_cohort_TAF.sql` | `lung_inpatient_records_orig`, `lung_ospatient_records_orig` (2016+) | `cms_source.taf_inpatient_header`, `cms_source.taf_other_services_header` | `ICD910_lung_cancer_codes` (derived from PhecodeX `CA_102.1` by `../reference/build_reference_tables.sql`) |
| `exposure_chemo_immuno_TAF.sql` | `chemo_ospatient_records`, `immuno_ospatient_records` (2016+) | `cms_source.taf_other_services_line` | `chemo_cpt_codes`, `immuno_cpt_codes` (12 HCPCS each, permanent J-codes + pre-approval C-codes) |
| `outcome_autoimmune_TAF.sql` | `autoimmune_inpatient_records[_v2]` from `taf_inpatient_header` (12 DGNS cols); `autoimmune_ospatient_records[_v2]` from `taf_other_services_header` (2 DGNS cols) — both 2016+ | `cms_source.taf_inpatient_header`, `cms_source.taf_other_services_header` | `autoimmune_icd` (PhecodeX seed — 14 anchors, ~1700 ICDs) |

Three concepts encoded here that an agent has to internalize:

1. **Diagnoses come from the header (wide DGNS_CD_1..10), treatments come
   from the line table (LINE_PRCDR_CD).** This split is unique to TAF and
   the source of many agent-generated bugs.

2. **Wide → tall pivot** (`_v2` tables). Whenever a claim row can contain
   up to N code columns and you want one row per (patient, code) for
   downstream aggregation, the N-way UNION is canonical. Diabetes step_2
   does the same thing for sex/race; here it's done for the autoimmune
   outcome.

3. **Schema-era gate.** Every cursor filter here includes `year_num >=
   2016`. The MAX era (pre-2016) uses different column names
   (`DIAG_CD_1..9`, `YR_NUM`, `EL_DOB`) and is handled separately by
   `lung_cohort_MAX.sql`. TAF 2016 was historically handled by a
   parallel pipeline (the TAF-2016 parallel pipeline) using regex-based HCPCS matching; since
   our `chemo_cpt_codes` / `immuno_cpt_codes` include pre-approval
   C-codes, exact-match works across all TAF years and the parallel
   branch is unnecessary.

The procedures above are verbatim excerpts of the gold-standard pipeline
with formatting cleanup only.
