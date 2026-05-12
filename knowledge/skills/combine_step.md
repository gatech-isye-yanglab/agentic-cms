# Skill: Combine Step (Step 2) — Disease-Agnostic

## Purpose
Union all 6 extraction output tables into a single normalized table `all_combine`.
This step is IDENTICAL across all diseases — only the source table names
(produced by step 1 extraction) change.

## all_combine schema (fixed, disease-agnostic)

```sql
DROP TABLE IF EXISTS all_combine;
CREATE TABLE all_combine (
    patient_id   VARCHAR(40),
    BENE_ID      VARCHAR(15),
    STATE_CD     VARCHAR(2),
    state_key    INT,
    YR_NUM       INT,
    BIRTH_DT     DATE,
    srvc_bgn_dt  DATE,
    srvc_end_dt  DATE,
    DIAG_CD_1    VARCHAR(8),
    DIAG_CD_2    VARCHAR(8),
    DIAG_CD_3    VARCHAR(8),
    DIAG_CD_4    VARCHAR(8),
    DIAG_CD_5    VARCHAR(8),
    DIAG_CD_6    VARCHAR(8),
    DIAG_CD_7    VARCHAR(8),
    DIAG_CD_8    VARCHAR(8),
    DIAG_CD_9    VARCHAR(8),
    DIAG_CD_10   VARCHAR(7),
    DIAG_CD_11   VARCHAR(7),
    DIAG_CD_12   VARCHAR(7)
);
```

## Insert pattern per era

ERA1 (inpatient, DIAG_CD_1..9):
```sql
INSERT INTO all_combine (patient_id, BENE_ID, STATE_CD, state_key, YR_NUM,
    srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, ..., DIAG_CD_9)
SELECT patient_id, BENE_ID, STATE_CD, state_key, YR_NUM,
    srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, ..., DIAG_CD_9
FROM {Re_all_inpatient};
```

ERA3 TAF (taf_inpatient_header, DGNS_CD_ → normalized to DIAG_CD_):
```sql
INSERT INTO all_combine (patient_id, BENE_ID, STATE_CD, state_key, YR_NUM,
    srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, ..., DIAG_CD_12)
SELECT PATIENT_ID, BENE_ID, STATE_CD, STATE_KEY, RFRNC_YR,
    srvc_bgn_dt, srvc_end_dt, DGNS_CD_1, ..., DGNS_CD_12
FROM {Re_All_taf_inpatient_header};
```

## Notes
- EL_DOB → BIRTH_DT normalization: ERA1/2 use EL_DOB; TAF uses BIRTH_DT.
  all_combine uses BIRTH_DT for all eras.
- EL_SEX_CD, EL_RACE_ETHNCY_CD are dropped in all_combine (not in schema).
- YR_NUM for ERA1/2 maps to RFRNC_YR for TAF — both stored in YR_NUM column.
- The table names in FROM clauses are the OUTPUT_TABLE_MAP values from the
  disease profile (step 1 outputs).
