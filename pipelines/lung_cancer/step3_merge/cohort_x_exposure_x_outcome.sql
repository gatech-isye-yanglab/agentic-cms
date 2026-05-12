-- =====================================================================
-- Step 3 — Merge cohort × exposure × outcome into treatment-arm tables
--
-- Source: gold-standard SQL (TAF-era cohort)
--   lung_chemo_patients                          — lines 2612-2619
--   lung_immuno_patients                         — lines 2755-2762
--   lung_chemo_autoimmune_patient                — lines 2518-2525
--   lung_immuno_autoimmune_patient               — lines 2635-2642
--   lung_chemo_autoimmune_patient_info_v1        — lines 2541-2550
--   lung_immuno_autoimmune_patient_info_v1       — lines 2658-2667
--   lung_chemo_autoimmune_patient_info_v2        — lines 2566-2596 (dedup repeated patients)
--   lung_immuno_autoimmune_patient_info_v2       — lines 2683-2713 (dedup repeated patients)
-- Owner:  gold-standard SQL author
--
-- Pipeline shape:
--
--   lung_patient_srt  ⋈ chemo_ospatient_srt  =  lung_chemo_patients
--   lung_patient_srt  ⋈ immuno_ospatient_srt =  lung_immuno_patients
--
--   lung_chemo_patients  ⟕ autoimmune_patient_srt  =  lung_chemo_autoimmune_patient
--   lung_immuno_patients ⟕ autoimmune_patient_srt  =  lung_immuno_autoimmune_patient
--
--   Attach demographics from taf_demog_elig_base  ->  *_info_v1
--   Dedup repeated patient_ids within *_info_v1   ->  *_info_v2
--
-- Inner join on the exposure tables is intentional: a patient enters the
-- chemo arm only if they appear in both lung_patient_srt AND
-- chemo_ospatient_srt. The autoimmune outcome is LEFT-joined because
-- absence of an autoimmune diagnosis is itself the data point (censoring).
--
-- Patients who appear in BOTH treatment arms are not removed here — that
-- filter happens in step 4 (v4 rule: mixed-therapy exclusion).
-- =====================================================================

-- ---- lung_chemo_patients (cohort × chemo) --------------------------

DELIMITER ;;
CREATE PROCEDURE `lung_chemo_patients`()
BEGIN
create table lung_chemo_patients as
select t1.*, t2.first_chemo_dt, t2.last_chemo_dt,
       t2.chemo_state, t2.chemo_yr, t2.cpt_cd
from lung_patient_srt t1 inner join chemo_ospatient_srt t2
  on t1.patient_id = t2.patient_id;
END ;;
DELIMITER ;

-- ---- lung_immuno_patients (cohort × immuno) ------------------------

DELIMITER ;;
CREATE PROCEDURE `lung_immuno_patients`()
BEGIN
create table lung_immuno_patients as
select t1.*, t2.first_immuno_dt, t2.last_immuno_dt,
       t2.immuno_state, t2.immuno_yr, t2.cpt_cd
from lung_patient_srt t1 inner join immuno_ospatient_srt t2
  on t1.patient_id = t2.patient_id;
END ;;
DELIMITER ;

-- ---- lung_chemo_autoimmune_patient (attach outcome) ----------------

DELIMITER ;;
CREATE PROCEDURE `lung_chemo_autoimmune_patient`()
BEGIN
create table lung_chemo_autoimmune_patient as
select t1.*, t2.first_autoimmune_dt, t2.last_autoimmune_dt,
       t2.autoimmune_state, t2.autoimmune_yr, t2.autoimmune_code
from lung_chemo_patients t1
left join autoimmune_patient_srt t2 on t1.patient_id = t2.patient_id;
END ;;
DELIMITER ;

-- ---- lung_immuno_autoimmune_patient (attach outcome) ---------------

DELIMITER ;;
CREATE PROCEDURE `lung_immuno_autoimmune_patient`()
BEGIN
create table lung_immuno_autoimmune_patient as
select t1.*, t2.first_autoimmune_dt, t2.last_autoimmune_dt,
       t2.autoimmune_state, t2.autoimmune_yr, t2.autoimmune_code
from lung_immuno_patients t1
left join autoimmune_patient_srt t2 on t1.patient_id = t2.patient_id;
END ;;
DELIMITER ;

-- ---- *_info_v1 (attach demographics from taf_demog_elig_base) ------

DELIMITER ;;
CREATE PROCEDURE `lung_chemo_autoimmune_patient_info_v1`()
BEGIN
drop table if exists lung_chemo_autoimmune_patient_info_v1;
create table lung_chemo_autoimmune_patient_info_v1 as
select t1.*, t2.BIRTH_DT as el_dob, t2.SEX_CD, t2.RACE_ETHNCTY_CD
from lung_chemo_autoimmune_patient t1
left join cms_source.taf_demog_elig_base t2
  on t2.state_key = substring_index(t1.lung_state, ',', 1)
 and t2.rfrnc_yr  = substring_index(t1.lung_yr, ',', 1)
 and t1.patient_id = t2.patient_id;
END ;;
DELIMITER ;

DELIMITER ;;
CREATE PROCEDURE `lung_immuno_autoimmune_patient_info_v1`()
BEGIN
drop table if exists lung_immuno_autoimmune_patient_info_v1;
create table lung_immuno_autoimmune_patient_info_v1 as
select t1.*, t2.BIRTH_DT as el_dob, t2.SEX_CD, t2.RACE_ETHNCTY_CD
from lung_immuno_autoimmune_patient t1
left join cms_source.taf_demog_elig_base t2
  on t2.state_key = substring_index(t1.lung_state, ',', 1)
 and t2.rfrnc_yr  = substring_index(t1.lung_yr, ',', 1)
 and t1.patient_id = t2.patient_id;
END ;;
DELIMITER ;

-- ---- *_info_v2 (dedup repeated patient_id rows) --------------------

DELIMITER ;;
CREATE PROCEDURE `lung_chemo_autoimmune_patient_info_v2`()
BEGIN
create table lung_chemo_autoimmune_patient_info_v1_repid as
  select patient_id, count(*) as cnt from lung_chemo_autoimmune_patient_info_v1
  group by patient_id having cnt > 1;

create table lung_chemo_autoimmune_patient_info_v1_repid_records as
  select * from lung_chemo_autoimmune_patient_info_v1
  where patient_id in (select patient_id from lung_chemo_autoimmune_patient_info_v1_repid);

create table lung_chemo_autoimmune_patient_info_v2 as
  select * from lung_chemo_autoimmune_patient_info_v1;

delete from lung_chemo_autoimmune_patient_info_v2
 where patient_id in (select patient_id from lung_chemo_autoimmune_patient_info_v1_repid);

insert into lung_chemo_autoimmune_patient_info_v2
  select patient_id, min(birth_dt) as birth_dt,
         min(first_lung_dt) first_lung_dt, min(last_lung_dt) last_lung_dt,
         min(lung_state) lung_state, min(lung_yr) lung_yr,
         min(first_chemo_dt) first_chemo_dt, min(last_chemo_dt) last_chemo_dt,
         min(chemo_state) chemo_state, min(chemo_yr) chemo_yr, min(cpt_cd) cpt_cd,
         min(first_autoimmune_dt) first_autoimmune_dt, min(last_autoimmune_dt) last_autoimmune_dt,
         min(autoimmune_state) autoimmune_state, min(autoimmune_yr) autoimmune_yr,
         min(autoimmune_code) autoimmune_code, min(el_dob) el_dob,
         min(SEX_CD) as SEX_CD, min(RACE_ETHNCTY_CD) RACE_ETHNCTY_CD
  from lung_chemo_autoimmune_patient_info_v1_repid_records group by patient_id;
END ;;
DELIMITER ;

DELIMITER ;;
CREATE PROCEDURE `lung_immuno_autoimmune_patient_info_v2`()
BEGIN
create table lung_immuno_autoimmune_patient_info_v1_repid as
  select patient_id, count(*) as cnt from lung_immuno_autoimmune_patient_info_v1
  group by patient_id having cnt > 1;

create table lung_immuno_autoimmune_patient_info_v1_repid_records as
  select * from lung_immuno_autoimmune_patient_info_v1
  where patient_id in (select patient_id from lung_immuno_autoimmune_patient_info_v1_repid);

create table lung_immuno_autoimmune_patient_info_v2 as
  select * from lung_immuno_autoimmune_patient_info_v1;

delete from lung_immuno_autoimmune_patient_info_v2
 where patient_id in (select patient_id from lung_immuno_autoimmune_patient_info_v1_repid);

insert into lung_immuno_autoimmune_patient_info_v2
  select patient_id, min(birth_dt) as birth_dt,
         min(first_lung_dt) first_lung_dt, min(last_lung_dt) last_lung_dt,
         min(lung_state) lung_state, min(lung_yr) lung_yr,
         min(first_immuno_dt) first_immuno_dt, min(last_immuno_dt) last_immuno_dt,
         min(immuno_state) immuno_state, min(immuno_yr) immuno_yr, min(cpt_cd) cpt_cd,
         min(first_autoimmune_dt) first_autoimmune_dt, min(last_autoimmune_dt) last_autoimmune_dt,
         min(autoimmune_state) autoimmune_state, min(autoimmune_yr) autoimmune_yr,
         min(autoimmune_code) autoimmune_code, min(el_dob) el_dob,
         min(SEX_CD) as SEX_CD, min(RACE_ETHNCTY_CD) RACE_ETHNCTY_CD
  from lung_immuno_autoimmune_patient_info_v1_repid_records group by patient_id;
END ;;
DELIMITER ;

call lung_chemo_patients();
call lung_immuno_patients();
call lung_chemo_autoimmune_patient();
call lung_immuno_autoimmune_patient();
call lung_chemo_autoimmune_patient_info_v1();
call lung_immuno_autoimmune_patient_info_v1();
call lung_chemo_autoimmune_patient_info_v2();
call lung_immuno_autoimmune_patient_info_v2();
