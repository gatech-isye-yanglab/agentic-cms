-- =====================================================================
-- Step 1c — Exposure (treatment) extraction, TAF era (2016+)
--
-- Source: gold-standard SQL (TAF-era cohort)
--   chemo_ospatient_records   — lines 1020-1069
--   immuno_ospatient_records  — lines 1993-2042
--   chemo_loop, immuno_loop   — earlier duplicate versions (lines 954, 1927)
-- Owner:  gold-standard SQL author
-- Reads:  cms_source.taf_other_services_line   (LINE_PRCDR_CD for HCPCS)
--         chemo_cpt_codes, immuno_cpt_codes
--           (see ../reference/README.md; 28 chemo HCPCS + 6 immuno J-codes + 6 C-codes)
-- Writes: <scratch_db>.chemo_ospatient_records, <scratch_db>.immuno_ospatient_records
--
-- Why line-level (not header-level):
--   Treatment identification in TAF uses HCPCS procedure codes, which live
--   on the LINE-level table (taf_other_services_line), NOT the header.
--   LINE_PRCDR_CD is the canonical field. This is different from the
--   diabetes pipeline (which uses diagnosis codes off the header).
--
-- Scope: year_num >= 2016 (all TAF era). The chemo_cpt_codes /
-- immuno_cpt_codes reference tables include pre-approval C-codes, so
-- the exact-match JOIN catches 2016 claims too — no need for the TAF-2016 parallel pipeline's
-- separate 2016 regex pipeline.
-- =====================================================================

-- ---- chemo_ospatient_records ---------------------------------------

DELIMITER ;;
CREATE PROCEDURE `chemo_ospatient_records`()
begin
	declare st_key int;
	declare year_num int;
    declare done boolean default 0;

	declare cur1 cursor for
		select sc.state_key, dy.year_num
		from cms_source.state_codes sc, cms_source.data_years dy
		where dy.year_num >= 2016
		order by sc.state_key, dy.year_num;

    declare continue handler for not found set done = 1;
    open cur1;

	create table if not exists chemo_ospatient_records (
        patient_id varchar(40),
        SRVC_BGN_DT date, SRVC_END_DT date, LINE_PRCDR_CD_DT date,
        cpt_cd varchar(45),
        state_key int, RFRNC_YR int
    );
read_loop: loop
    create table if not exists chemo_ospatient_records_check (state_key int, RFRNC_YR int);
		fetch cur1 into st_key, year_num;
		if done then leave read_loop; end if;
		insert into chemo_ospatient_records
		(select t1.patient_id, t1.LINE_SRVC_BGN_DT, t1.LINE_SRVC_END_DT,
                t1.LINE_PRCDR_CD_DT, t1.LINE_PRCDR_CD, t1.state_key, t1.RFRNC_YR
         from cms_source.taf_other_services_line t1, chemo_cpt_codes t2
         where state_key = st_key and rfrnc_yr = year_num
           and t1.LINE_PRCDR_CD = t2.cpt_code);
        insert into chemo_ospatient_records_check (select st_key, year_num);
		commit;
	end loop;
end ;;
DELIMITER ;

-- ---- immuno_ospatient_records --------------------------------------

DELIMITER ;;
CREATE PROCEDURE `immuno_ospatient_records`()
begin
	declare st_key int;
	declare year_num int;
    declare done boolean default 0;

	declare cur1 cursor for
		select sc.state_key, dy.year_num
		from cms_source.state_codes sc, cms_source.data_years dy
		where dy.year_num >= 2016
		order by sc.state_key, dy.year_num;

    declare continue handler for not found set done = 1;
    open cur1;

	create table if not exists immuno_ospatient_records (
        patient_id varchar(40),
        SRVC_BGN_DT date, SRVC_END_DT date, LINE_PRCDR_CD_DT date,
        cpt_cd varchar(45),
        state_key int, RFRNC_YR int
    );
read_loop: loop
    create table if not exists immuno_ospatient_records_check (state_key int, RFRNC_YR int);
		fetch cur1 into st_key, year_num;
		if done then leave read_loop; end if;
		insert into immuno_ospatient_records
		(select t1.patient_id, t1.LINE_SRVC_BGN_DT, t1.LINE_SRVC_END_DT,
                t1.LINE_PRCDR_CD_DT, t1.LINE_PRCDR_CD, t1.state_key, t1.RFRNC_YR
         from cms_source.taf_other_services_line t1, immuno_cpt_codes t2
         where state_key = st_key and rfrnc_yr = year_num
           and t1.LINE_PRCDR_CD = t2.cpt_code);
        insert into immuno_ospatient_records_check (select st_key, year_num);
		commit;
	end loop;
end ;;
DELIMITER ;

call chemo_ospatient_records();
call immuno_ospatient_records();
