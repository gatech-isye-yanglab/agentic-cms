# Diabetes Cohort Pipeline — Gold-Standard SQL

A reproducible CMS Medicaid claims pipeline that identifies an incident
diabetes cohort across the three CMS schema eras (MAX 2005–2012,
MAX 2013–2015, TAF 2016+) and consolidates it into one row per patient
with sex / race / date-of-birth / first-and-second diagnosis dates.

This is the validation case for the multi-agent prototype: an end-to-end
pipeline that a senior biostatistician produced over months, that the
agent should be able to reproduce on the synthetic CMS sandbox in hours.

**Cohort:** ≥2 qualifying diabetes claims on different service dates within
a 730-day window, restricted to the 7 SE states (AL, FL, GA, MS, NC, SC, TN).
Step 4 (the 24-month criterion) is currently hard-coded to GA, so the final
output is a Georgia cohort. Loosening to all 7 states is a one-line edit.

---

## Architecture — two parallel lanes

The CMS schema splits patient attributes across two kinds of tables:
**claims** (one row per service date, carries diagnosis codes) and
**eligibility / personal summary** (one row per beneficiary per year,
carries sex / race / DOB / death). To preserve demographics across the
pipeline, claims and demographics are processed as two parallel lanes
that join at Step 5.

```
                     CLAIMS LANE                    DEMOGRAPHICS LANE
                     ───────────                    ─────────────────
Step 1    Re_all_inpatient, Re_all_inpatient1315,   Re_personal_summary,
          Re_all_other_therapy, Re_all_other_       Re_personal_summary1315,
          therapy1315, Re_All_taf_inpatient,        Re_taf_demog_elig_base
          Re_All_other_services_header                 │
             │                                         │
Step 2       ↓                                         ↓
          all_combine                              all_combine_demo
          (patient / date / diag codes)            (patient / sex / race / BIRTH_DT)
             │                                         │
Step 3       ↓                                         ↓
          All_Selected_state                      All_Selected_state_demo
          (7 SE states)                            (7 SE states)
             │                                         │
Step 4       ↓                                         │
          temp_all_in_two_years_GA                     │
          (GA only; 24-month flag)                     │
             │                                         │
Step 5       ↓                                         │
          patient_flag_summary_GA                      │
          (1st + 2nd diab dx dates)                    │
             │                                         │
             ↓                                         │
          single_row_patient_temp  ◄──── (UPDATE ... JOIN) ────┘
          ── FINAL TABLE, one row per patient ──
```

`single_row_patient_temp` is the final analytical output. The `_temp` suffix
is a legacy of an earlier refactor; it's the canonical table.

---

## Execution order

### Step 1 — Reference tables

| File | Purpose |
|---|---|
| [`reference/icd_code.sql`](reference/icd_code.sql) | ICD-10 ↔ ICD-9 mapping (87 pairs) |
| [`reference/hcpcs_code.sql`](reference/hcpcs_code.sql) | HCPCS diabetes management codes (56) |
| [`reference/icd_9_cm.sql`](reference/icd_9_cm.sql) | ICD-9 lookup table for joins |

### Step 2 — Extract from 9 source tables (run in any order)

**Claims lane** (6 tables):

| File | Source era |
|---|---|
| [`step1_extraction/Re_all_inpatient.sql`](step1_extraction/Re_all_inpatient.sql) | Inpatient 2005–2012 (MAX) |
| [`step1_extraction/Re_all_inpatient1315.sql`](step1_extraction/Re_all_inpatient1315.sql) | Inpatient 2013–2015 (MAX) |
| [`step1_extraction/Re_all_other_therapy.sql`](step1_extraction/Re_all_other_therapy.sql) | Outpatient 2005–2012 (MAX) |
| [`step1_extraction/Re_all_other_therapy1315.sql`](step1_extraction/Re_all_other_therapy1315.sql) | Outpatient 2013–2015 (MAX) |
| [`step1_extraction/Re_All_other_services_header.sql`](step1_extraction/Re_All_other_services_header.sql) | Outpatient 2016+ (TAF) |
| [`step1_extraction/Re_All_taf_inpatient.sql`](step1_extraction/Re_All_taf_inpatient.sql) | Inpatient 2016+ (TAF) |

**Demographics lane** (3 tables):

| File | Source era |
|---|---|
| [`step1_extraction/Re_personal_summary.sql`](step1_extraction/Re_personal_summary.sql) | Personal summary 2005–2012 (MAX) |
| [`step1_extraction/Re_personal_summary1315.sql`](step1_extraction/Re_personal_summary1315.sql) | Personal summary 2013–2015 (MAX) |
| [`step1_extraction/Re_taf_demog_elig_base.sql`](step1_extraction/Re_taf_demog_elig_base.sql) | TAF demographics 2016+ |

### Step 3 — Combine per lane

- [`step2_combine/all_combine.sql`](step2_combine/all_combine.sql) — unions the 6 claims tables into `all_combine`.
- [`step2_combine/all_combine_demo.sql`](step2_combine/all_combine_demo.sql) — unions the 3 demographics tables into `all_combine_demo`, harmonising MAX-era column names (`EL_DOB`, `EL_SEX_CD`, `EL_RACE_ETHNCY_CD`, `YEAR_NUM`) onto TAF-era names (`BIRTH_DT`, `SEX_CD`, `ETHNCTY_CD`, `RFRNC_YR → YR_NUM`).

### Step 4 — Filter to 7 SE states (AL, FL, GA, MS, NC, SC, TN)

- [`step3_filter/all_selected_state.sql`](step3_filter/all_selected_state.sql) → `All_Selected_state` (claims).
- [`step3_filter/all_selected_state_demo.sql`](step3_filter/all_selected_state_demo.sql) → `All_Selected_state_demo` (demographics).

### Step 5 — Apply 24-month incident criterion (GA only)

- [`step4_two_year/all_in_two_years.sql`](step4_two_year/all_in_two_years.sql) → `temp_all_in_two_years_GA` with `(patient_id, srvc_bgn_DT, appears_within_2_years)`. Uses a set-based `EXISTS` subquery to flag whether any later service date for the same patient falls within 730 days. GA-only (`state_CD = 'GA'` is hard-coded).

### Step 6 — Consolidate; identify 1st + 2nd diagnosis dates

- [`step5_consolidate/step_2.sql`](step5_consolidate/step_2.sql):
  - Builds `patient_flag_summary_GA` — for each patient with at least two qualifying claims within 730 days, records `1st_diab_DIAG_DT` and `2nd_diab_DIAG_DT`.
  - Builds `single_row_patient_temp` by joining `All_Selected_state` at the first diagnosis date and aggregating all 12 diagnosis columns into `full_diag_cd_list` via `CONCAT_WS(',', GROUP_CONCAT(...))`.

### Step 7 — Attach ambiguity-resolved demographics

- [`step5_consolidate/step_3.sql`](step5_consolidate/step_3.sql):
  - `ALTER TABLE single_row_patient_temp` to widen `STATE_CD` to `VARCHAR(10)` (so it can hold the `'Ambiguous'` sentinel) and add `SEX_CD` and `ETHNCTY_CD` columns.
  - `UPDATE ... JOIN` against `All_Selected_state_demo`, grouping by `PATIENT_ID`. If a patient has conflicting values across demographic records (`COUNT(DISTINCT ...) > 1`), the field is set to `'Ambiguous'`; `BIRTH_DT` is set to `NULL` in that case.

`single_row_patient_temp` is the final analytical output — one row per
patient, GA cohort.

---

## Running it

```bash
# Against the synthetic CMS sandbox (default db name: diabetes_pipeline):
bash run_pipeline.sh

# With your own MySQL credentials:
DB_USER=foo DB_PASS=bar DB_NAME=mydb bash run_pipeline.sh
```

Prerequisites:
1. MySQL reachable at `127.0.0.1:3306` with the `cms_source` schema populated
   — see [`../../synthetic_data/`](../../synthetic_data/) for the schema-exact synthetic
   sandbox.
2. The reference tables (`icd_9_cm`, `ICD code`, `HCPCS_Codes`) must exist
   in the working DB; `run_pipeline.sh` runs the `reference/*.sql` files
   first.

---

## Database constraints

All queries against a real institutional CMS Medicaid database **must**
filter on `state_key` **and** `year_num` / `RFRNC_YR`. Unpartitioned
queries get killed by the institutional production server. The cursor
pattern in every step-1 file iterates over `(state, year)` pairs to
satisfy this rule — see
[`../../knowledge/skills/extraction_cursor.md`](../../knowledge/skills/extraction_cursor.md).

Also: set MySQL Workbench DBMS connection read timeout to `600s` or long
queries will fail.
