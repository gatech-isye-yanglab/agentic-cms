# Prompt 06 — 5-stage gold-standard pipelines

## Goal

Generate `pipelines/diabetes/` and `pipelines/lung_cancer/` — the two
canonical 5-stage gold-standard SQL pipelines. Plus a stub
`pipelines/pancreas/` with a forward-looking README.

The Schema Agent / SQL Writer / Critic infrastructure (prompts 02-05)
is what *generates* this kind of code at runtime. The hand-written
gold-standard versions exist as the **target shape** the agent's
output must converge on.

## Files to generate

### pipelines/diabetes/ — 21 files

```
pipelines/diabetes/
├── README.md
├── reference/
│   ├── icd_9_cm.sql              (drop+create+insert ~29 ICD-9 codes)
│   ├── icd_code.sql              (drop+create+insert ~87 ICD-10↔ICD-9 pairs into `ICD code` table)
│   └── hcpcs_code.sql            (drop+create+insert ~58 HCPCS codes)
├── step1_extraction/
│   ├── Re_all_inpatient.sql      (MAX 2005-2012 inpatient extraction)
│   ├── Re_all_inpatient1315.sql  (MAX 2013-2015)
│   ├── Re_all_other_therapy.sql  (MAX 2005-2012 outpatient)
│   ├── Re_all_other_therapy1315.sql  (MAX 2013-2015)
│   ├── Re_All_taf_inpatient.sql  (TAF 2016+ inpatient)
│   ├── Re_All_other_services_header.sql  (TAF 2016+ outpatient)
│   ├── Re_personal_summary.sql   (MAX 2005-2012 demographics)
│   ├── Re_personal_summary1315.sql  (MAX 2013-2015 demographics)
│   └── Re_taf_demog_elig_base.sql   (TAF 2016+ demographics)
├── step2_combine/
│   ├── all_combine.sql           (claims lane: 6 unions into all_combine)
│   └── all_combine_demo.sql      (demographics lane: 3 unions into all_combine_demo)
├── step3_filter/
│   ├── all_selected_state.sql    (claims lane: filter to 7 SE states)
│   └── all_selected_state_demo.sql  (demographics lane: same filter)
├── step4_two_year/
│   └── all_in_two_years.sql      (24-month criterion, GA only)
├── step5_consolidate/
│   ├── step_2.sql                (patient_flag_summary_GA + single_row_patient_temp)
│   └── step_3.sql                (attach demographics with ambiguity resolution)
└── run_pipeline.sh               (end-to-end orchestrator)
```

### Two-parallel-lane architecture

The diabetes pipeline has **two parallel lanes**:

- **Claims lane**: 6 source tables → `all_combine` → `All_Selected_state` → `temp_all_in_two_years_GA` → `patient_flag_summary_GA` → `single_row_patient_temp`.
- **Demographics lane**: 3 source tables → `all_combine_demo` → `All_Selected_state_demo` → joined into `single_row_patient_temp` at Step 5.

Why two lanes: the CMS schema splits patient attributes across claims
(one row per service date, carries diagnosis codes) and eligibility/
personal_summary tables (one row per beneficiary per year, carries
sex/race/DOB). An earlier monolithic pipeline tried to thread
demographics through the claims lane and dropped them during combine,
forcing Step 5 to re-read Step 1 outputs. The two-lane version is
the honest architecture; reproduce it.

### Step-1 stored procedures — shape

Each `Re_*.sql` follows the cursor pattern from prompt 04:

```sql
DROP TABLE IF EXISTS Re_all_inpatient;
CREATE TABLE Re_all_inpatient (
  -- columns matching cms_source.inpatient with backtick-quoted, era-correct names
  patient_id varchar(40), BENE_ID varchar(15), STATE_CD varchar(2),
  state_key int, YR_NUM int, EL_DOB date, EL_SEX_CD varchar(1),
  EL_RACE_ETHNCY_CD varchar(1), SRVC_BGN_DT date, SRVC_END_DT date,
  DIAG_CD_1 varchar(8), ..., DIAG_CD_9 varchar(8)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DELIMITER $$
CREATE PROCEDURE Re_all_inpatient_loop()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_state_key INT;
    DECLARE v_year_num INT;
    DECLARE cur1 CURSOR FOR
        SELECT sc.state_key, dy.year_num
        FROM cms_source.state_codes sc, cms_source.data_years dy
        WHERE dy.year_num BETWEEN 2005 AND 2012
        ORDER BY sc.state_key, dy.year_num;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
    OPEN cur1;
    read_loop: LOOP
        FETCH cur1 INTO v_state_key, v_year_num;
        IF done THEN LEAVE read_loop; END IF;
        INSERT INTO Re_all_inpatient
        SELECT patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, EL_DOB,
               EL_SEX_CD, EL_RACE_ETHNCY_CD, SRVC_BGN_DT, SRVC_END_DT,
               DIAG_CD_1, ..., DIAG_CD_9
        FROM cms_source.inpatient inp
        WHERE inp.state_key = v_state_key
          AND inp.YR_NUM = v_year_num
          AND (
              inp.DIAG_CD_1 IN (SELECT codes FROM cms_source.icd_9_cm) OR
              inp.DIAG_CD_2 IN (SELECT codes FROM cms_source.icd_9_cm) OR
              ... OR
              inp.DIAG_CD_9 IN (SELECT codes FROM cms_source.icd_9_cm)
          );
    END LOOP;
    CLOSE cur1;
END$$
DELIMITER ;
CALL Re_all_inpatient_loop();
```

ERA-specific variants:
- ERA2 (`Re_all_inpatient1315`): same shape, `WHERE dy.year_num BETWEEN 2013 AND 2015`. Uses ICD-9 IN OR ICD-10 LIKE.
- ERA3 TAF (`Re_All_taf_inpatient`, `Re_All_other_services_header`): substitute `DGNS_CD_1..12` (or `..2` for outpatient), `RFRNC_YR`, `STATE_KEY`, `BIRTH_DT`. Uses ICD-10 LIKE OR ICD-9 IN.

### Step-2 combine

`all_combine.sql`: drop+create the unified table per
`combine_step.md` skill, then 6 INSERT-SELECTs (one per Step-1
output). TAF inserts rename `PATIENT_ID→patient_id`, `RFRNC_YR→YR_NUM`,
`DGNS_CD_*→DIAG_CD_*`, `STATE_KEY→state_key`.

`all_combine_demo.sql`: similar but for the 3 demographics tables;
harmonizes ERA1/2 column names (`EL_DOB→BIRTH_DT`, `EL_SEX_CD→SEX_CD`,
`EL_RACE_ETHNCY_CD→ETHNCTY_CD`, `YEAR_NUM→YR_NUM`).

### Step-3 SE-state filter

Trivial: `CREATE TABLE All_Selected_state AS SELECT * FROM all_combine
WHERE STATE_CD IN ('AL','FL','GA','MS','NC','SC','TN');` and same for
`_demo`.

### Step-4 two-year criterion (GA only)

`all_in_two_years.sql`: produces `temp_all_in_two_years_GA(patient_id,
SRVC_BGN_DT, appears_within_2_years)`. Uses set-based EXISTS subquery
(NOT a cursor) to flag whether any later service date for the same
patient falls within 730 days. **Hardcoded to `state_CD = 'GA'`** —
this is a known limitation; document it.

### Step-5 consolidate (two SQL files)

`step_2.sql`:

1. Build `patient_flag_summary_GA(patient_id, 1st_diab_DIAG_DT,
   2nd_diab_DIAG_DT)` for patients with at least 2 qualifying claims
   within 730 days.
2. Build `single_row_patient_temp` by joining `All_Selected_state`
   at the first diagnosis date, aggregating all 12 DIAG_CD_*
   columns into `full_diag_cd_list` via
   `CONCAT_WS(',', GROUP_CONCAT(...))`.

`step_3.sql`:

1. ALTER `single_row_patient_temp` to widen `STATE_CD` to `VARCHAR(10)`
   (so it can hold the `'Ambiguous'` sentinel) and add `SEX_CD`,
   `ETHNCTY_CD` columns.
2. UPDATE … JOIN against `All_Selected_state_demo`, GROUP BY
   `PATIENT_ID`. If `COUNT(DISTINCT field) > 1`, set the field to
   `'Ambiguous'`; for `BIRTH_DT` (a date), set NULL.

### run_pipeline.sh

```bash
#!/usr/bin/env bash
set -e
DB_NAME=${DB_NAME:-diabetes_pipeline}
mysql -u root -e "DROP DATABASE IF EXISTS $DB_NAME; CREATE DATABASE $DB_NAME ..."
# Then for each SQL file, sed-normalize whitespace-indented comment
# lines so the mysql client recognizes DELIMITER as a client-side
# directive, then pipe to mysql with sql_mode='' (relax NO_ZERO_DATE
# for taf_demog_elig_base sentinel dates).
```

The full ordered list: ref tables (3) → claims-lane Step-1 (6) →
demographics-lane Step-1 (3) → Step-2 combines (2) → Step-3 filters
(2) → Step-4 (1) → Step-5 step_2 + step_3 (2). Total 19 SQL files
in order.

### pipelines/lung_cancer/ — similar shape, more complex

A 5-stage parallel structure but for lung-cancer + autoimmune
adverse-event study. The lung-cancer pipeline is **larger than
diabetes** — roughly 2× the SQL line count concentrated in Step 5.
Cold-decompression v1 truncated this section; v2 must not.

#### Files

- `step1_extraction/`: 5 SQL files —
  - `lung_cohort_MAX.sql` (2005–2012 lung-cancer cohort, ICD-9 inline list)
  - `lung_cohort_MAX1315.sql` (2013–2015)
  - `lung_cohort_TAF.sql` (2016+; joins `ICD910_lung_cancer_codes`)
  - `exposure_chemo_immuno_TAF.sql` (joins `chemo_cpt_codes` / `immuno_cpt_codes`)
  - `outcome_autoimmune_TAF.sql` (joins `autoimmune_icd`; emits both wide and tall `_v2` formats)
  Plus a `README.md` describing the diagnoses-from-header /
  treatments-from-line split that's unique to TAF.
- `step2_per_patient_summary/srt_tables.sql` — collapses each Step-1
  output into a single-row-table-per-patient via GROUP BY + MIN/MAX
  date aggregation.
- `step3_merge/cohort_x_exposure_x_outcome.sql` — joins cohort × exposure × outcome.
- `step4_demographics_and_criteria/`:
  - `inclusion_and_covariates.sql` — applies inclusion criteria
    (age, study window); stages outputs as `v3 → v4 → v6 → v7`.
    The v3/v4/v6/v7 naming is load-bearing — it's referenced in
    `final_tables.sql` and the published-thesis methodology.
  - `prep_entire_records_and_covariates.sql` — backfills 2016-era
    dates from a parallel TAF-2016 pipeline.
- `step5_consolidate/final_tables.sql` — Cox-ready survival tables.
  **This is the largest file in the pipeline** (~30 per-drug /
  per-disease subgroup tables, each a UNION of TAF-2017+ and
  TAF-2016 results). Concrete shape per subgroup:

  ```sql
  -- Per drug, e.g. nivolumab (NI):
  DROP TABLE IF EXISTS chemo_NI_final;
  CREATE TABLE chemo_NI_final AS
  SELECT *, 0 AS treatment FROM lung_chemo_autoimmune_patient_v7
   WHERE drug = 'NI'
  UNION ALL
  SELECT *, 0 AS treatment FROM chemo_table_2016_v3
   WHERE drug = 'NI';

  -- Per disease, e.g. type-1 diabetes (T1):
  DROP TABLE IF EXISTS immuno_T1_final;
  CREATE TABLE immuno_T1_final AS
  SELECT *, 1 AS treatment FROM lung_immuno_autoimmune_patient_v7
   WHERE autoimmune_event IN (SELECT icd910 FROM autoimmune_icd_dm)
  UNION ALL
  SELECT *, 1 AS treatment FROM immuno_table_2016_T1_v3;
  ```

  Generate ALL of: 6 per-drug chemo (NI, PE, AT, DI, AV, IP) + 6
  per-drug immuno × 5 per-disease (T1, hypo, RA, thyroiditis,
  myalgia) overall tables + 2 chemo/immuno aggregate finals.
  Approximate file length: 300+ lines of SQL.

- `reference/build_reference_tables.sql` — populates 4 tables in
  `<scratch_db>.{ICD910_lung_cancer_codes, autoimmune_icd,
  immuno_cpt_codes, chemo_cpt_codes}` from the public PhecodeX CSVs
  in `cohort_identification/databases/phewas/` plus an inline ICD
  list.
- `reference/autoimmune_sub_slices.sql` — emits per-disease subset
  tables: `autoimmune_icd_dm`, `autoimmune_icd_hypo`,
  `autoimmune_icd_ra`, `autoimmune_icd_thyroiditis`,
  `autoimmune_icd_myalgia`. Each is a `CREATE TABLE AS SELECT … FROM
  autoimmune_icd WHERE phecode_anchor IN (…)`.
- 4 `*_legacy_claims.md` provenance docs — see prompt 07's
  `examples/phewas_anchor_reference.md` for the legacy-claims paper
  citation pattern. These are HCPCS / ICD lists with one-paragraph
  rationale each; ~50 lines each.
- `run_pipeline.sh`, `run_step1.sh` — orchestrators.
- `README.md` with honest "gold standard with noise" framing:
  reference tables were purged from the production server, so
  `build_reference_tables.sql` reconstructs them from PhecodeX + the
  inline MAX-era ICD list. Row-count ground truth is pending.

**Cold-decompression v1 left lung_cancer Step 5 at one NI+T1 union;
that's wrong.** Generate the full ~30 subgroup tables. If you run
out of budget, document which subgroups are missing rather than
silently shipping a truncated final_tables.sql.

### pipelines/pancreas/ — stub only

A README-only stub:

```markdown
# Pancreas Cohort Pipeline — Forthcoming

**Status:** stub. The pancreas-cohort pipeline (planned third disease
in the diabetes/lung-cancer/pancreas trio) is not yet implemented.
This folder is a placeholder so the top-level layout reflects the
intended scope.

## Plan

Adapter from pipelines/lung_cancer/, with PhecodeX `CA_101.5` anchor,
`C25.*` (ICD-10) + `157.*` (ICD-9) children, pancreatic-cancer-
specific chemo HCPCS (gemcitabine J9201, FOLFIRINOX components), etc.

The agent project's premise is that this adapter should be generated
by the multi-agent prototype itself given a NL pancreas-cancer
protocol description, not hand-coded.
```

## Critical: scrubbing reminders

The full-repo SQL has been scrubbed of internal student names,
schema prefixes (`<scratch_db>.` not e.g. `ysun614.`), and Aetna
references. When regenerating, **do not reintroduce them**.

## Validation

After this prompt completes:

- `bash pipelines/diabetes/run_pipeline.sh` against a populated
  `cms_source` MySQL DB (from prompt 08's `toy_db/`) completes
  end-to-end and produces a non-empty `single_row_patient_temp`.
- `bash pipelines/lung_cancer/run_pipeline.sh` runs to completion;
  Step 5 final tables exist (chemo arm row count may be small or
  zero on toy_db given the 1,000-patient scale; document this).

## See also

- Full-repo equivalents at `pipelines/{diabetes,lung_cancer,pancreas}/`.
- Prompts 03+04+05 for the constraints, skills, and disease profile that this pipeline encodes.
- Prompt 08 for the toy_db fixture and tests that validate this.
