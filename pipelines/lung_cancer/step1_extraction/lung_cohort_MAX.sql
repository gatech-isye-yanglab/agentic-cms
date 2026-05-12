-- =====================================================================
-- Step 1a — Lung cancer cohort extraction, MAX era 2005–2012
--
-- Source: gold-standard SQL (MAX-era cohort, partner-collated) — many `all_inpatient_lung_cancer_N`
-- procedures per state; consolidated here into one cursor-over-(state × year)
-- pattern that mirrors the TAF extractor in lung_cohort_TAF.sql.
-- Owner:  the MAX-era pipeline → tightened by orchestrator (Phase E)
-- Reads:  cms_source.inpatient, cms_source.other_therapy  (MAX 2005–2012)
--         ICD910_lung_cancer_codes  (built by ../reference/build_reference_tables.sql)
-- Writes: lung_inpatient_records_MAX, lung_ospatient_records_MAX
--
-- Schema harmonization at extract time (same pattern diabetes uses in
-- ../diabetes/step2_combine/all_combine.sql):
--   MAX column name  →  unified TAF-shaped output
--   DIAG_CD_1..9     →  DGNS_CD_1..9       (DGNS_CD_10..12 stay NULL)
--   YR_NUM           →  RFRNC_YR
--   EL_DOB           →  BIRTH_DT
--
-- Rationale: step2_per_patient_summary/srt_tables.sql does a 6-way UNION
-- across (TAF in, TAF os, MAX in, MAX os, MAX1315 in, MAX1315 os) to
-- produce lung_patient_records. Matching the TAF-shaped column names
-- here makes that UNION trivial (no per-branch column aliasing at
-- step 2).
--
-- Scope: cohort (diagnosis) only. MAX-era chemo/immuno exposure is
-- skipped by design — immunotherapy was not FDA-approved for lung cancer
-- until March 2015, so pre-2016 exposure data has near-zero signal. MAX
-- patients are included so they can be joined with TAF-era treatment
-- claims for patients diagnosed pre-2016 but treated post-2016.
-- =====================================================================

-- ---- lung_inpatient_records_MAX -----------------------------------------

DELIMITER ;;
CREATE PROCEDURE `lung_inpatient_records_MAX`()
begin
    declare st_key int;
    declare year_num int;
    declare done boolean default 0;

    declare cur1 cursor for
        select sc.state_key, dy.year_num
        from cms_source.state_codes sc, cms_source.data_years dy
        where dy.year_num between 2005 and 2012
        order by sc.state_key, dy.year_num;

    declare continue handler for not found set done = 1;

    open cur1;
    create table if not exists lung_inpatient_records_MAX (
        patient_id varchar(40),
        BIRTH_DT   date,
        SRVC_BGN_DT date,
        SRVC_END_DT date,
        DGNS_CD_1 varchar(7), DGNS_CD_2 varchar(7), DGNS_CD_3 varchar(7),
        DGNS_CD_4 varchar(7), DGNS_CD_5 varchar(7), DGNS_CD_6 varchar(7),
        DGNS_CD_7 varchar(7), DGNS_CD_8 varchar(7), DGNS_CD_9 varchar(7),
        state_key int, RFRNC_YR int
    );
read_loop: loop
    fetch cur1 into st_key, year_num;
    if done then leave read_loop; end if;
    insert into lung_inpatient_records_MAX
    (select patient_id, EL_DOB, SRVC_BGN_DT, SRVC_END_DT,
            DIAG_CD_1, DIAG_CD_2, DIAG_CD_3, DIAG_CD_4, DIAG_CD_5,
            DIAG_CD_6, DIAG_CD_7, DIAG_CD_8, DIAG_CD_9,
            state_key, YR_NUM
     from cms_source.inpatient t1, ICD910_lung_cancer_codes t2
     where state_key = st_key and YR_NUM = year_num
     and (t1.DIAG_CD_1 = t2.icd910 or t1.DIAG_CD_2 = t2.icd910 or
          t1.DIAG_CD_3 = t2.icd910 or t1.DIAG_CD_4 = t2.icd910 or
          t1.DIAG_CD_5 = t2.icd910 or t1.DIAG_CD_6 = t2.icd910 or
          t1.DIAG_CD_7 = t2.icd910 or t1.DIAG_CD_8 = t2.icd910 or
          t1.DIAG_CD_9 = t2.icd910));
    commit;
end loop;
end ;;
DELIMITER ;

-- ---- lung_ospatient_records_MAX (MAX outpatient, 2 DGNS cols) ----------

DELIMITER ;;
CREATE PROCEDURE `lung_ospatient_records_MAX`()
begin
    declare st_key int;
    declare year_num int;
    declare done boolean default 0;

    declare cur1 cursor for
        select sc.state_key, dy.year_num
        from cms_source.state_codes sc, cms_source.data_years dy
        where dy.year_num between 2005 and 2012
        order by sc.state_key, dy.year_num;

    declare continue handler for not found set done = 1;

    open cur1;
    create table if not exists lung_ospatient_records_MAX (
        patient_id varchar(40),
        BIRTH_DT   date,
        SRVC_BGN_DT date,
        SRVC_END_DT date,
        DGNS_CD_1 varchar(7), DGNS_CD_2 varchar(7),
        state_key int, RFRNC_YR int
    );
read_loop: loop
    fetch cur1 into st_key, year_num;
    if done then leave read_loop; end if;
    insert into lung_ospatient_records_MAX
    (select patient_id, EL_DOB, SRVC_BGN_DT, SRVC_END_DT,
            DIAG_CD_1, DIAG_CD_2,
            state_key, YR_NUM
     from cms_source.other_therapy t1, ICD910_lung_cancer_codes t2
     where state_key = st_key and YR_NUM = year_num
     and (t1.DIAG_CD_1 = t2.icd910 or t1.DIAG_CD_2 = t2.icd910));
    commit;
end loop;
end ;;
DELIMITER ;

call lung_inpatient_records_MAX();
call lung_ospatient_records_MAX();
