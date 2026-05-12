-- =====================================================================
-- step4 prep — build the intermediate tables that the gold-standard preserved SQL
-- references but never defines. Run BEFORE inclusion_and_covariates.sql.
--
-- Semantic notes from the gold-standard header comments in inclusion_and_covariates.sql:
--   utilization = count of claim rows in the 1 year prior to diagnosis
--                 (inpatient + outpatient)
--   sickness    = number of distinct ICD codes before diagnosis
--   first/last record = study observation window (all-claims, not just
--                 lung-cancer-matching)
--
-- Depends on:
--   cms_source.taf_inpatient_header, cms_source.taf_other_services_header
--   lung_patient_srt  (built by step2_per_patient_summary/srt_tables.sql)
--   chemo_ospatient_srt, immuno_ospatient_srt
-- =====================================================================

-- ---- patient_for_all_records_srt ------------------------------------
-- In the gold-standard preserved SQL this is referenced by record_before_diagnosis
-- and has columns (patient_id, lung_state, lung_yr, first_lung_dt).
-- That shape matches lung_patient_srt exactly — the two names are used
-- interchangeably in the preserved code. Materialise it as a copy for
-- clarity (same semantics, different downstream consumer).
DROP TABLE IF EXISTS patient_for_all_records_srt;
CREATE TABLE patient_for_all_records_srt AS
SELECT patient_id, BIRTH_DT, first_lung_dt, last_lung_dt, lung_state, lung_yr
FROM lung_patient_srt;
CREATE INDEX idx_pfars_pid ON patient_for_all_records_srt(patient_id);

-- ---- entire_records_inpatient / _ospatient --------------------------
-- Full MAX + TAF claim-level rows restricted to cohort patients. Used
-- by step4's first_last_record_in / first_last_record_os procedures to
-- compute the study observation window (first / last claim date per
-- patient across all claims, not just lung-matching ones) and by the
-- utilization / sickness covariate calculations below.
--
-- Why UNION MAX + TAF here: since Phase E extended the cohort to
-- 2005-2018 (MAX + TAF), the pre-diagnosis window for a MAX-era patient
-- lives in cms_source.inpatient or .inpatient1315, not the TAF tables.
-- Restricting entire_records_* to TAF-only would give MAX patients a
-- silent-zero utilization/sickness — a covariate bug, not just a
-- missing feature. TAF column shape is the canonical output; MAX
-- columns are aliased at UNION time (DIAG_CD_n → DGNS_CD_n for n=1..9,
-- NULL for DGNS_CD_10..12; YR_NUM → RFRNC_YR).
--
-- Scoping to cohort via patient_id IN (patient_for_all_records_srt)
-- rather than pulling every cms_source row keeps the tables small.

DROP TABLE IF EXISTS entire_records_inpatient;
CREATE TABLE entire_records_inpatient AS
SELECT patient_id, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR,
       DGNS_CD_1,  DGNS_CD_2,  DGNS_CD_3,  DGNS_CD_4,  DGNS_CD_5,  DGNS_CD_6,
       DGNS_CD_7,  DGNS_CD_8,  DGNS_CD_9,  DGNS_CD_10, DGNS_CD_11, DGNS_CD_12
FROM cms_source.taf_inpatient_header
WHERE RFRNC_YR >= 2016
  AND patient_id IN (SELECT patient_id FROM patient_for_all_records_srt)
UNION ALL
SELECT patient_id, SRVC_BGN_DT, SRVC_END_DT, state_key, YR_NUM,
       DIAG_CD_1, DIAG_CD_2, DIAG_CD_3, DIAG_CD_4, DIAG_CD_5, DIAG_CD_6,
       DIAG_CD_7, DIAG_CD_8, DIAG_CD_9, NULL, NULL, NULL
FROM cms_source.inpatient
WHERE patient_id IN (SELECT patient_id FROM patient_for_all_records_srt)
UNION ALL
SELECT patient_id, SRVC_BGN_DT, SRVC_END_DT, state_key, YR_NUM,
       DIAG_CD_1, DIAG_CD_2, DIAG_CD_3, DIAG_CD_4, DIAG_CD_5, DIAG_CD_6,
       DIAG_CD_7, DIAG_CD_8, DIAG_CD_9, NULL, NULL, NULL
FROM cms_source.inpatient1315
WHERE patient_id IN (SELECT patient_id FROM patient_for_all_records_srt);
CREATE INDEX idx_eri_pid ON entire_records_inpatient(patient_id);

DROP TABLE IF EXISTS entire_records_ospatient;
CREATE TABLE entire_records_ospatient AS
SELECT patient_id, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR,
       DGNS_CD_1, DGNS_CD_2
FROM cms_source.taf_other_services_header
WHERE RFRNC_YR >= 2016
  AND patient_id IN (SELECT patient_id FROM patient_for_all_records_srt)
UNION ALL
SELECT patient_id, SRVC_BGN_DT, SRVC_END_DT, state_key, YR_NUM,
       DIAG_CD_1, DIAG_CD_2
FROM cms_source.other_therapy
WHERE patient_id IN (SELECT patient_id FROM patient_for_all_records_srt)
UNION ALL
SELECT patient_id, SRVC_BGN_DT, SRVC_END_DT, state_key, YR_NUM,
       DIAG_CD_1, DIAG_CD_2
FROM cms_source.other_therapy1315
WHERE patient_id IN (SELECT patient_id FROM patient_for_all_records_srt);
CREATE INDEX idx_ero_pid ON entire_records_ospatient(patient_id);

-- ---- entire_records_before_diag_in / _os ----------------------------
-- Same rows restricted to the 365-day utilization window BEFORE the
-- patient's first lung-cancer claim. Step4's utilization procedure does
-- COUNT(*) over these; step4's sickness definition counts distinct ICDs
-- across both (we materialise that one below).

DROP TABLE IF EXISTS entire_records_before_diag_in;
CREATE TABLE entire_records_before_diag_in AS
SELECT e.*
FROM entire_records_inpatient e
JOIN patient_for_all_records_srt p ON p.patient_id = e.patient_id
WHERE DATEDIFF(p.first_lung_dt, e.SRVC_BGN_DT) BETWEEN 1 AND 365;
CREATE INDEX idx_erbdi_pid ON entire_records_before_diag_in(patient_id);

DROP TABLE IF EXISTS entire_records_before_diag_os;
CREATE TABLE entire_records_before_diag_os AS
SELECT e.*
FROM entire_records_ospatient e
JOIN patient_for_all_records_srt p ON p.patient_id = e.patient_id
WHERE DATEDIFF(p.first_lung_dt, e.SRVC_BGN_DT) BETWEEN 1 AND 365;
CREATE INDEX idx_erbdo_pid ON entire_records_before_diag_os(patient_id);

-- ---- sickness ------------------------------------------------------
-- Count of DISTINCT diagnosis codes across both inpatient and outpatient
-- claims in the pre-diagnosis window, per patient. Referenced by v6_table
-- in inclusion_and_covariates.sql.

DROP TABLE IF EXISTS sickness;
CREATE TABLE sickness AS
SELECT patient_id, COUNT(DISTINCT DGNS_CD) AS sickness
FROM (
    SELECT patient_id, DGNS_CD_1  AS DGNS_CD FROM entire_records_before_diag_in WHERE DGNS_CD_1  IS NOT NULL AND DGNS_CD_1  <> '' UNION
    SELECT patient_id, DGNS_CD_2          FROM entire_records_before_diag_in WHERE DGNS_CD_2  IS NOT NULL AND DGNS_CD_2  <> '' UNION
    SELECT patient_id, DGNS_CD_3          FROM entire_records_before_diag_in WHERE DGNS_CD_3  IS NOT NULL AND DGNS_CD_3  <> '' UNION
    SELECT patient_id, DGNS_CD_4          FROM entire_records_before_diag_in WHERE DGNS_CD_4  IS NOT NULL AND DGNS_CD_4  <> '' UNION
    SELECT patient_id, DGNS_CD_5          FROM entire_records_before_diag_in WHERE DGNS_CD_5  IS NOT NULL AND DGNS_CD_5  <> '' UNION
    SELECT patient_id, DGNS_CD_6          FROM entire_records_before_diag_in WHERE DGNS_CD_6  IS NOT NULL AND DGNS_CD_6  <> '' UNION
    SELECT patient_id, DGNS_CD_7          FROM entire_records_before_diag_in WHERE DGNS_CD_7  IS NOT NULL AND DGNS_CD_7  <> '' UNION
    SELECT patient_id, DGNS_CD_8          FROM entire_records_before_diag_in WHERE DGNS_CD_8  IS NOT NULL AND DGNS_CD_8  <> '' UNION
    SELECT patient_id, DGNS_CD_9          FROM entire_records_before_diag_in WHERE DGNS_CD_9  IS NOT NULL AND DGNS_CD_9  <> '' UNION
    SELECT patient_id, DGNS_CD_10         FROM entire_records_before_diag_in WHERE DGNS_CD_10 IS NOT NULL AND DGNS_CD_10 <> '' UNION
    SELECT patient_id, DGNS_CD_11         FROM entire_records_before_diag_in WHERE DGNS_CD_11 IS NOT NULL AND DGNS_CD_11 <> '' UNION
    SELECT patient_id, DGNS_CD_12         FROM entire_records_before_diag_in WHERE DGNS_CD_12 IS NOT NULL AND DGNS_CD_12 <> '' UNION
    SELECT patient_id, DGNS_CD_1          FROM entire_records_before_diag_os WHERE DGNS_CD_1  IS NOT NULL AND DGNS_CD_1  <> '' UNION
    SELECT patient_id, DGNS_CD_2          FROM entire_records_before_diag_os WHERE DGNS_CD_2  IS NOT NULL AND DGNS_CD_2  <> ''
) t
GROUP BY patient_id;
CREATE INDEX idx_sickness_pid ON sickness(patient_id);

-- ---- single_row_table_2016 (empty stub, semantically redundant) ----
-- v7_table (in inclusion_and_covariates.sql) LEFT JOINs against this
-- table to backfill 2016-era dates. Historically the TAF-2016 parallel pipeline maintained it
-- as part of a separate 2016-only pipeline; in the unified TAF 2016+
-- pipeline the 2016 dates flow through the main v3..v7 chain directly,
-- so the backfill is a no-op. We still materialise an empty table so
-- v7_table's LEFT JOIN runs cleanly (empty table → NULL backfill, which
-- is the correct "nothing to merge" outcome).
DROP TABLE IF EXISTS single_row_table_2016;
CREATE TABLE single_row_table_2016 (
    PATIENT_ID           VARCHAR(40),
    First_DT_Lung_Cancer DATE,
    SRVC_Chemo_Date      DATE,
    SRVC_Immuno_Date     DATE,
    SRVC_Autoimmune_Date DATE
);

-- ---- immuno_and_chemo_id -------------------------------------------
-- Patients who appear in BOTH treatment arms — used by v4_table's
-- "clean exposure" rule (drop mixed-therapy patients).

DROP TABLE IF EXISTS immuno_and_chemo_id;
CREATE TABLE immuno_and_chemo_id AS
SELECT i.patient_id
FROM immuno_ospatient_srt i
JOIN chemo_ospatient_srt  c ON c.patient_id = i.patient_id;
CREATE INDEX idx_iaci_pid ON immuno_and_chemo_id(patient_id);

-- ---- Row-count summary ---------------------------------------------
SELECT 'patient_for_all_records_srt',   COUNT(*) FROM patient_for_all_records_srt   UNION ALL
SELECT 'entire_records_inpatient',      COUNT(*) FROM entire_records_inpatient      UNION ALL
SELECT 'entire_records_ospatient',      COUNT(*) FROM entire_records_ospatient      UNION ALL
SELECT 'entire_records_before_diag_in', COUNT(*) FROM entire_records_before_diag_in UNION ALL
SELECT 'entire_records_before_diag_os', COUNT(*) FROM entire_records_before_diag_os UNION ALL
SELECT 'sickness',                      COUNT(*) FROM sickness                      UNION ALL
SELECT 'immuno_and_chemo_id',           COUNT(*) FROM immuno_and_chemo_id;
