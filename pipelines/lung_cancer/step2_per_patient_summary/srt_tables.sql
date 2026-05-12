-- =====================================================================
-- Step 2 — Per-patient summary (_srt tables: one row per patient)
--
-- Source: gold-standard SQL (TAF-era cohort)
--   lung_patient_srt         — lines 2940-2952
--   immuno_ospatient_srt     — lines 2059-2071
--   chemo_ospatient_srt      — lines 1086-1098
--   autoimmune_patient_srt   — lines 886-911
-- Owner:  gold-standard SQL author
--
-- What _srt means in the gold-standard naming: "single-row table" — the result of
-- collapsing all claim-level rows for a patient into one row using
-- min/max dates and GROUP_CONCAT for codes.
--
-- Pattern:
--   1. For each topic (lung / chemo / immuno / autoimmune), union the
--      inpatient + outpatient (or line-level) records together.
--   2. Group by patient_id.
--   3. Emit first/last service dates, state/year lists, and concatenated
--      code strings.
--
-- This is the lung-cancer analogue of diabetes step5_consolidate/step_2.sql
-- — same consolidation move, but done separately for the cohort, each
-- treatment arm, and the outcome, because downstream merges need them as
-- separate per-patient tables.
--
-- Critical config: `set session group_concat_max_len = 10000;` — without
-- this, the autoimmune_code and cpt_cd fields get truncated for heavy users.
-- =====================================================================

-- ---- lung_patient_srt (the cohort) ---------------------------------

DELIMITER ;;
CREATE PROCEDURE `lung_patient_srt`()
BEGIN
-- 6-way UNION over the three schema eras × two claim lanes. Each branch
-- was produced by step1 with the TAF-shaped column naming (BIRTH_DT /
-- RFRNC_YR), so no per-branch aliasing is needed here.
create table lung_patient_records as
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR from lung_inpatient_records_orig       union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR from lung_ospatient_records_orig       union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR from lung_inpatient_records_MAX        union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR from lung_ospatient_records_MAX        union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR from lung_inpatient_records_MAX1315    union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR from lung_ospatient_records_MAX1315;

create table lung_patient_srt as
select patient_id,
       min(BIRTH_DT)    as BIRTH_DT,
       min(SRVC_BGN_DT) as first_lung_dt,
       max(SRVC_END_DT) as last_lung_dt,
       group_concat(distinct state_key) as lung_state,
       group_concat(distinct RFRNC_YR) as lung_yr
from lung_patient_records group by patient_id;
END ;;
DELIMITER ;

-- ---- immuno_ospatient_srt (immunotherapy arm) ----------------------

DELIMITER ;;
CREATE PROCEDURE `immuno_ospatient_srt`()
BEGIN
drop table if exists immuno_ospatient_srt;
set session group_concat_max_len = 10000;
create table immuno_ospatient_srt as
select patient_id,
       min(SRVC_BGN_DT)     as first_immuno_dt,
       max(SRVC_END_DT)     as last_immuno_dt,
       min(LINE_PRCDR_CD_DT) as first_cpt_dt,
       group_concat(distinct cpt_cd)    as cpt_cd,
       group_concat(distinct state_key) as immuno_state,
       group_concat(distinct RFRNC_YR)  as immuno_yr
from immuno_ospatient_records group by patient_id;
END ;;
DELIMITER ;

-- ---- chemo_ospatient_srt (chemotherapy arm) ------------------------

DELIMITER ;;
CREATE PROCEDURE `chemo_ospatient_srt`()
BEGIN
drop table if exists chemo_ospatient_srt;
set session group_concat_max_len = 10000;
create table chemo_ospatient_srt as
select patient_id,
       min(SRVC_BGN_DT)     as first_chemo_dt,
       max(SRVC_END_DT)     as last_chemo_dt,
       min(LINE_PRCDR_CD_DT) as first_cpt_dt,
       group_concat(distinct cpt_cd)    as cpt_cd,
       group_concat(distinct state_key) as chemo_state,
       group_concat(distinct RFRNC_YR)  as chemo_yr
from chemo_ospatient_records group by patient_id;
END ;;
DELIMITER ;

-- ---- autoimmune_patient_srt (outcome) ------------------------------

DELIMITER ;;
CREATE PROCEDURE `autoimmune_patient_srt`()
BEGIN
create table autoimmune_patient_records as
  select * from autoimmune_ospatient_records_v2
  union
  select * from autoimmune_inpatient_records_v2;
create index id_idx on autoimmune_patient_records(patient_id);

create table earliest_autoimmune_dt as
select patient_id, min(SRVC_BGN_DT) as first_autoimmune_DT
from autoimmune_patient_records group by patient_id;
create index id_idx on earliest_autoimmune_dt(patient_id);

create table autoimmune_patient_earliest as
select t1.patient_id, t1.BIRTH_DT, t2.first_autoimmune_dt,
       t1.SRVC_END_DT as last_autoimmune_dt, t1.DGNS_CD,
       t1.state_key, t1.RFRNC_YR
from autoimmune_patient_records t1 inner join earliest_autoimmune_dt t2
  on t1.patient_id = t2.patient_id and t1.SRVC_BGN_DT = t2.first_autoimmune_dt;

set session group_concat_max_len = 10000;
create table autoimmune_patient_srt
select patient_id,
       min(BIRTH_DT)               as BIRTH_DT,
       min(first_autoimmune_dt)    as first_autoimmune_dt,
       max(last_autoimmune_dt)     as last_autoimmune_dt,
       group_concat(distinct state_key) as autoimmune_state,
       group_concat(distinct RFRNC_YR)  as autoimmune_yr,
       group_concat(distinct DGNS_CD)   as autoimmune_code
from autoimmune_patient_earliest group by patient_id;
END ;;
DELIMITER ;

call lung_patient_srt();
call immuno_ospatient_srt();
call chemo_ospatient_srt();
call autoimmune_patient_srt();
