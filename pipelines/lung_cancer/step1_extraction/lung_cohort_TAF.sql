-- =====================================================================
-- Step 1b — Lung cancer cohort extraction, TAF era (2016+)
--
-- Source: gold-standard SQL (TAF-era cohort)
--   lung_inpatient_records_orig  — lines 2778-2855
--   lung_ospatient_records_orig  — lines 2871-2924
-- Owner:  gold-standard SQL author — TAF era
-- Reads:  cms_source.taf_inpatient_header, cms_source.taf_other_services_header
--         ICD910_lung_cancer_codes  (built by ../reference/build_reference_tables.sql)
-- Writes: lung_inpatient_records_orig, lung_ospatient_records_orig
--         (no `<scratch_db>.` prefix — reference tables now live in the current DB)
--
-- Schema-era notes:
--   TAF renames DIAG_CD_* → DGNS_CD_*, adds DGNS_CD_10 (10 columns not 9),
--   replaces YR_NUM with RFRNC_YR, renames EL_DOB → BIRTH_DT, and
--   drops EL_SEX_CD / EL_RACE_ETHNCY_CD from the claim row (demographics
--   live on taf_demog_elig_base instead — attached in step3_merge).
--
-- Scope: year_num >= 2016 (all TAF era). the gold-standard original used
-- year_num >= 2017 because the TAF-2016 parallel pipeline handled 2016 via a separate regex-
-- based pipeline (see ../gold-standard SQL (TAF-2016 parallel pipeline)). Since our
-- chemo_cpt_codes / immuno_cpt_codes reference tables now include the
-- pre-approval C-codes the TAF-2016 parallel pipeline's regex was designed to catch, the
-- unified pipeline handles 2016 exact-match correctly and the separate
-- branch is unnecessary.
-- =====================================================================

-- ---- lung_inpatient_records_orig (TAF 2016+ inpatient) --------------

DELIMITER ;;
CREATE PROCEDURE `lung_inpatient_records_orig`()
begin
	declare st_key int;
	declare st_cd varchar(2);
	declare year_num int;
    declare done boolean default 0;

	declare cur1 cursor for
		select sc.state_key, dy.year_num
		from cms_source.state_codes sc, cms_source.data_years dy
		where dy.year_num >= 2016
		order by sc.state_key, dy.year_num;

    declare continue handler for not found set done = 1;

    open cur1;
	create table if not exists lung_inpatient_records_orig (
        patient_id varchar(40),
        BIRTH_DT   date,
        SRVC_BGN_DT date,
        SRVC_END_DT date,
        DGNS_CD_1 varchar(7), DGNS_CD_2 varchar(7), DGNS_CD_3 varchar(7),
        DGNS_CD_4 varchar(7), DGNS_CD_5 varchar(7), DGNS_CD_6 varchar(7),
        DGNS_CD_7 varchar(7), DGNS_CD_8 varchar(7), DGNS_CD_9 varchar(7),
        DGNS_CD_10 varchar(7),
        state_key int, RFRNC_YR int
    );
read_loop: loop
    create table if not exists lung_inpatient_records_orig_check (state_key int, RFRNC_YR int);
		fetch cur1 into st_key, year_num;
		if done then leave read_loop; end if;
		insert into lung_inpatient_records_orig
		(select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT,
                DGNS_CD_1, DGNS_CD_2, DGNS_CD_3, DGNS_CD_4, DGNS_CD_5,
                DGNS_CD_6, DGNS_CD_7, DGNS_CD_8, DGNS_CD_9, DGNS_CD_10,
                state_key, RFRNC_YR
         from cms_source.taf_inpatient_header t1, ICD910_lung_cancer_codes t2
         where state_key = st_key and rfrnc_yr = year_num
         and (t1.DGNS_CD_1 = t2.icd910 or t1.DGNS_CD_2 = t2.icd910 or
              t1.DGNS_CD_3 = t2.icd910 or t1.DGNS_CD_4 = t2.icd910 or
              t1.DGNS_CD_5 = t2.icd910 or t1.DGNS_CD_6 = t2.icd910 or
              t1.DGNS_CD_7 = t2.icd910 or t1.DGNS_CD_8 = t2.icd910 or
              t1.DGNS_CD_9 = t2.icd910 or t1.DGNS_CD_10 = t2.icd910));
        insert into lung_inpatient_records_orig_check (select st_key, year_num);
		commit;
	end loop;
end ;;
DELIMITER ;

-- ---- lung_ospatient_records_orig (TAF 2016+ outpatient, 2 DGNS cols) --

DELIMITER ;;
CREATE PROCEDURE `lung_ospatient_records_orig`()
begin
	declare st_key int;
	declare st_cd varchar(2);
	declare year_num int;
    declare done boolean default 0;

	declare cur1 cursor for
		select sc.state_key, dy.year_num
		from cms_source.state_codes sc, cms_source.data_years dy
		where dy.year_num >= 2016
		order by sc.state_key, dy.year_num;

    declare continue handler for not found set done = 1;

    open cur1;
	create table if not exists lung_ospatient_records_orig (
        patient_id varchar(40),
        BIRTH_DT   date,
        SRVC_BGN_DT date,
        SRVC_END_DT date,
        DGNS_CD_1 varchar(7), DGNS_CD_2 varchar(7),
        state_key int, RFRNC_YR int
    );
read_loop: loop
    create table if not exists lung_ospatient_records_orig_check (state_key int, RFRNC_YR int);
		fetch cur1 into st_key, year_num;
		if done then leave read_loop; end if;
		insert into lung_ospatient_records_orig
		(select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT,
                DGNS_CD_1, DGNS_CD_2, state_key, RFRNC_YR
         from cms_source.taf_other_services_header t1, ICD910_lung_cancer_codes t2
         where state_key = st_key and rfrnc_yr = year_num
         and (t1.DGNS_CD_1 = t2.icd910 or t1.DGNS_CD_2 = t2.icd910));
        insert into lung_ospatient_records_orig_check (select st_key, year_num);
		commit;
	end loop;
end ;;
DELIMITER ;

call lung_inpatient_records_orig();
call lung_ospatient_records_orig();
