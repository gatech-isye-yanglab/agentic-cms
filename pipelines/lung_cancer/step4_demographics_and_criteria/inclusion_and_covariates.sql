-- =====================================================================
-- Step 4 — Inclusion rules, first/last records, utilization, v3-v7 tables
--
-- Source: gold-standard SQL (TAF-era cohort)
--   first_last_record_in        — lines 1877-1886
--   first_last_record_os        — lines 1902-1911
--   first_last_record_dt        — lines 1852-1861
--   record_before_diagnosis     — lines 3063-3075
--   utilization                 — lines 3215-3224
--   v3_table                    — lines 3240-3249
--   v4 / v4_table               — lines 3265-3278 / 3294-3307
--   v6_table                    — lines 3323-3361
--   v7_table                    — lines 3377-3410
-- Owner:  gold-standard SQL author
--
-- This is the "human judgment" stage — where statistical inclusion rules
-- and covariates get layered onto the merged tables. These are the exact
-- design choices that require a statistician's / clinician's review, and
-- the point in the pipeline where an agent needs the strongest skill-file
-- guidance. The rules encoded here (v4) are the causal-design heart of
-- the published thesis / gold-standard publication.
--
-- v3 = attach entire-record first/last dates (study observation window)
-- v4 = apply 3 inclusion rules:
--        (a) patient NOT in both immuno AND chemo arms  (clean exposure)
--        (b) datediff(first_lung_dt, first_record_dt) >= 30 days
--              → 30-day quiescence, patient was not already in dataset sick
--        (c) first treatment date >= first lung cancer date
--              → treatment AFTER diagnosis (causal ordering check)
-- v5/v6 = attach utilization and sickness covariates, post-filter outcomes
-- v7 = backfill 2016-era dates from the TAF-2016 parallel pipeline's single_row_table_2016
--
-- Downstream covariate definitions:
--   utilization = count of claim rows in the 1 year prior to diagnosis
--                 (inpatient + outpatient, from entire_records_before_diag_*)
--   sickness    = number of distinct ICD codes before diagnosis
--                 (defined elsewhere; same "before lung cancer" window)
--   age         = datediff(first_lung_dt, BIRTH_DT) / 365
-- =====================================================================

-- ---- first_last_record_in / _os / _dt ------------------------------

DELIMITER ;;
CREATE PROCEDURE `first_last_record_in`()
BEGIN
create table first_last_record_in as
select patient_id,
       min(SRVC_BGN_DT) first_record_dt,
       max(SRVC_END_DT) last_record_dt,
       group_concat(distinct state_key) as record_state,
       group_concat(distinct RFRNC_YR) as record_year
from entire_records_inpatient group by patient_id;
END ;;
DELIMITER ;

DELIMITER ;;
CREATE PROCEDURE `first_last_record_os`()
BEGIN
create table first_last_record_os as
select patient_id,
       min(SRVC_BGN_DT) first_record_dt,
       max(SRVC_END_DT) last_record_dt,
       group_concat(distinct state_key) as record_state,
       group_concat(distinct RFRNC_YR) as record_year
from entire_records_ospatient group by patient_id;
END ;;
DELIMITER ;

DELIMITER ;;
CREATE PROCEDURE `first_last_record_dt`()
BEGIN
create table first_last_record_dt_raw as
  select patient_id, first_record_dt, last_record_dt from first_last_record_os
  union select patient_id, first_record_dt, last_record_dt from first_last_record_in;

create table first_last_record_dt as
select patient_id,
       min(first_record_dt) as first_record_dt,
       max(last_record_dt)  as last_record_dt
from first_last_record_dt_raw group by patient_id;
END ;;
DELIMITER ;

-- ---- record_before_diagnosis (sickness / utilization window) -------

DELIMITER ;;
CREATE PROCEDURE `record_before_diagnosis`()
BEGIN
create index id_idx on patient_for_all_records_srt(patient_id);
create table record_before_diagnosis as
select t1.*, t2.DGNS_CD_1, t2.DGNS_CD_2
from patient_for_all_records_srt t1
left join cms_source.taf_other_services_header t2
  on find_in_set(t2.state_key, t1.lung_state)
 and t2.rfrnc_yr <= substring_index(t1.lung_yr, ',', 1)
 and t1.patient_id = t2.patient_id
 and datediff(t1.first_lung_dt, t2.SRVC_BGN_DT) > 0
 and datediff(t1.first_lung_dt, t2.SRVC_BGN_DT) < 365;
END ;;
DELIMITER ;

-- ---- utilization (count of claims in the prior year) --------------

DELIMITER ;;
CREATE PROCEDURE `utilization`()
BEGIN
create table utilization_tmp as
  select patient_id, count(*) as cnt from entire_records_before_diag_in group by patient_id
  union all
  select patient_id, count(*) as cnt from entire_records_before_diag_os group by patient_id;

create table utilization as
  select patient_id, sum(cnt) as utilization
  from utilization_tmp group by patient_id;
END ;;
DELIMITER ;

-- ---- v3_table: attach first/last record dt -------------------------

DELIMITER ;;
CREATE PROCEDURE `v3_table`()
BEGIN
create table lung_chemo_autoimmune_patient_v3 as
select t1.*, t2.first_record_dt, t2.last_record_dt
from lung_chemo_autoimmune_patient_info_v2 t1
left join first_last_record_dt t2 on t1.patient_id = t2.patient_id;

create table lung_immuno_autoimmune_patient_v3 as
select t1.*, t2.first_record_dt, t2.last_record_dt
from lung_immuno_autoimmune_patient_info_v2 t1
left join first_last_record_dt t2 on t1.patient_id = t2.patient_id;
END ;;
DELIMITER ;

-- ---- v4_table: THE inclusion filter --------------------------------
-- 3 inclusion rules:
--   (a) patient NOT in immuno_and_chemo_id (clean exposure)
--   (b) datediff(first_lung_dt, first_record_dt) >= 30  (30-day quiescence)
--   (c) first treatment date >= first lung cancer date  (causal ordering)

DELIMITER ;;
CREATE PROCEDURE `v4_table`()
BEGIN
create table lung_immuno_autoimmune_patient_v4 as
select * from lung_immuno_autoimmune_patient_v3
where patient_id not in (select patient_id from immuno_and_chemo_id)
  and datediff(first_lung_dt, first_record_dt) >= 30
  and first_immuno_dt >= first_lung_dt;

create table lung_chemo_autoimmune_patient_v4 as
select * from lung_chemo_autoimmune_patient_v3
where patient_id not in (select patient_id from immuno_and_chemo_id)
  and datediff(first_lung_dt, first_record_dt) >= 30
  and first_chemo_dt >= first_lung_dt;
END ;;
DELIMITER ;

-- ---- v6_table: attach utilization + sickness covariates ------------

DELIMITER ;;
CREATE PROCEDURE `v6_table`()
BEGIN
create table lung_immuno_autoimmune_patient_v5 as
  select t1.*, t2.utilization from lung_immuno_autoimmune_patient_v4 t1
  left join utilization t2 on t1.patient_id = t2.patient_id;
create table lung_immuno_autoimmune_patient_v6 as
  select t1.*, t2.sickness from lung_immuno_autoimmune_patient_v5 t1
  left join sickness t2 on t1.patient_id = t2.patient_id;

create table lung_chemo_autoimmune_patient_v5 as
  select t1.*, t2.utilization from lung_chemo_autoimmune_patient_v4 t1
  left join utilization t2 on t1.patient_id = t2.patient_id;
create table lung_chemo_autoimmune_patient_v6 as
  select t1.*, t2.sickness from lung_chemo_autoimmune_patient_v5 t1
  left join sickness t2 on t1.patient_id = t2.patient_id;

update lung_chemo_autoimmune_patient_v6  set utilization = 0 where utilization is null;
update lung_chemo_autoimmune_patient_v6  set sickness    = 0 where sickness    is null;
update lung_immuno_autoimmune_patient_v6 set utilization = 0 where utilization is null;
update lung_immuno_autoimmune_patient_v6 set sickness    = 0 where sickness    is null;

-- post-filter: drop patients whose autoimmune record predates therapy
delete from lung_chemo_autoimmune_patient_v6  where first_autoimmune_dt <= first_chemo_dt;
delete from lung_immuno_autoimmune_patient_v6 where first_autoimmune_dt <= first_immuno_dt;
END ;;
DELIMITER ;

-- ---- v7_table: backfill 2016-era dates from the TAF-2016 parallel pipeline ---------------

DELIMITER ;;
CREATE PROCEDURE `v7_table`()
BEGIN
create table info_from_2016 as
select PATIENT_ID, First_DT_Lung_Cancer, SRVC_Chemo_Date, SRVC_Immuno_Date, SRVC_Autoimmune_Date
from single_row_table_2016
where patient_id in (select patient_id from lung_immuno_autoimmune_patient_v6)
   or patient_id in (select patient_id from lung_chemo_autoimmune_patient_v6);

create table lung_immuno_autoimmune_patient_v7 as
select t1.*, t2.First_DT_Lung_Cancer, t2.SRVC_Chemo_Date,
       t2.SRVC_Immuno_Date, t2.SRVC_Autoimmune_Date
from lung_immuno_autoimmune_patient_v6 t1
left join info_from_2016 t2 on t1.patient_id = t2.patient_id;

create table lung_chemo_autoimmune_patient_v7 as
select t1.*, t2.First_DT_Lung_Cancer, t2.SRVC_Chemo_Date,
       t2.SRVC_Immuno_Date, t2.SRVC_Autoimmune_Date
from lung_chemo_autoimmune_patient_v6 t1
left join info_from_2016 t2 on t1.patient_id = t2.patient_id;
END ;;
DELIMITER ;

call first_last_record_in();
call first_last_record_os();
call first_last_record_dt();
call utilization();
call v3_table();
call v4_table();
call v6_table();
call v7_table();
