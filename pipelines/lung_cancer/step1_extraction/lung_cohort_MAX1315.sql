-- =====================================================================
-- Step 1a.5 — Lung cancer cohort extraction, MAX era 2013–2015
--
-- Source: gold-standard SQL (MAX-era cohort, partner-collated) — per-state `all_inpatient_lung_cancer_N_1315`
-- procedures, consolidated into one cursor-over-(state × year) pattern
-- mirroring lung_cohort_MAX.sql.
-- Owner:  the MAX-era pipeline → tightened by orchestrator (Phase E)
-- Reads:  cms_source.inpatient1315, cms_source.other_therapy1315
--         ICD910_lung_cancer_codes  (built by ../reference/build_reference_tables.sql)
-- Writes: lung_inpatient_records_MAX1315, lung_ospatient_records_MAX1315
--
-- Why a separate file from lung_cohort_MAX.sql: the 1315 source tables
-- are a distinct CMS partition (transition-year split — ICD-9 was
-- replaced by ICD-10 on Oct 1, 2015, which is inside this window), so
-- CMS kept them in their own tables. Column shape is identical to MAX
-- 2005–2012, so the extraction code is a cut-and-paste with source-table
-- names swapped. This mirrors the diabetes `Re_all_inpatient1315` /
-- `Re_all_other_therapy1315` pattern.
--
-- Same output schema as lung_cohort_MAX.sql (DGNS_CD_* / BIRTH_DT /
-- RFRNC_YR) so step2's 6-way UNION can append these rows without
-- per-branch aliasing.
-- =====================================================================

-- ---- lung_inpatient_records_MAX1315 ------------------------------------

DELIMITER ;;
CREATE PROCEDURE `lung_inpatient_records_MAX1315`()
begin
    declare st_key int;
    declare year_num int;
    declare done boolean default 0;

    declare cur1 cursor for
        select sc.state_key, dy.year_num
        from cms_source.state_codes sc, cms_source.data_years dy
        where dy.year_num between 2013 and 2015
        order by sc.state_key, dy.year_num;

    declare continue handler for not found set done = 1;

    open cur1;
    create table if not exists lung_inpatient_records_MAX1315 (
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
    insert into lung_inpatient_records_MAX1315
    (select patient_id, EL_DOB, SRVC_BGN_DT, SRVC_END_DT,
            DIAG_CD_1, DIAG_CD_2, DIAG_CD_3, DIAG_CD_4, DIAG_CD_5,
            DIAG_CD_6, DIAG_CD_7, DIAG_CD_8, DIAG_CD_9,
            state_key, YR_NUM
     from cms_source.inpatient1315 t1, ICD910_lung_cancer_codes t2
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

-- ---- lung_ospatient_records_MAX1315 ------------------------------------

DELIMITER ;;
CREATE PROCEDURE `lung_ospatient_records_MAX1315`()
begin
    declare st_key int;
    declare year_num int;
    declare done boolean default 0;

    declare cur1 cursor for
        select sc.state_key, dy.year_num
        from cms_source.state_codes sc, cms_source.data_years dy
        where dy.year_num between 2013 and 2015
        order by sc.state_key, dy.year_num;

    declare continue handler for not found set done = 1;

    open cur1;
    create table if not exists lung_ospatient_records_MAX1315 (
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
    insert into lung_ospatient_records_MAX1315
    (select patient_id, EL_DOB, SRVC_BGN_DT, SRVC_END_DT,
            DIAG_CD_1, DIAG_CD_2,
            state_key, YR_NUM
     from cms_source.other_therapy1315 t1, ICD910_lung_cancer_codes t2
     where state_key = st_key and YR_NUM = year_num
     and (t1.DIAG_CD_1 = t2.icd910 or t1.DIAG_CD_2 = t2.icd910));
    commit;
end loop;
end ;;
DELIMITER ;

call lung_inpatient_records_MAX1315();
call lung_ospatient_records_MAX1315();
