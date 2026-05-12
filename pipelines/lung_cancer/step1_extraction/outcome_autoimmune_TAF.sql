-- =====================================================================
-- Step 1d — Outcome (autoimmune side-effect) extraction, TAF era (2016+)
--
-- Source: gold-standard SQL (TAF-era cohort)
--   autoimmune_inpatient_records    — lines 633-711  (10-way UNION, header)
--   autoimmune_ospatient_records    — lines 776-845  (2-way UNION, header)
--   autoimmune_inpatient_records_v2 — lines 727-760  (reshape to DGNS_CD col)
--   autoimmune_ospatient_records_v2 — lines 861-869  (reshape to DGNS_CD col)
-- Owner:  gold-standard SQL author
-- Reads:  cms_source.taf_inpatient_header       (inpatient autoimmune — 12 DGNS cols)
--         cms_source.taf_other_services_header  (outpatient autoimmune — 2 DGNS cols)
--         autoimmune_icd (built by ../reference/build_reference_tables.sql;
--           currently a minimal PhecodeX seed, ~14 anchors; not the full
--           ~56 Super-PheWAS rollup)
--
-- Departure from the gold-standard original: the gold standard reads BOTH inpatient and outpatient
-- autoimmune from `taf_other_services_header`. In our synthetic schema (and
-- likely the institutional) `taf_other_services_header` carries only DGNS_CD_1
-- and DGNS_CD_2, so reading DGNS_CD_3..DGNS_CD_10 off it fails with
-- "Unknown column". Switched the inpatient source to `taf_inpatient_header`
-- (which carries DGNS_CD_1..12); this is the semantically correct table
-- for inpatient diagnoses anyway.
-- Writes: <scratch_db>.autoimmune_inpatient_records,
--         <scratch_db>.autoimmune_inpatient_records_v2 (tall format),
--         <scratch_db>.autoimmune_ospatient_records,
--         <scratch_db>.autoimmune_ospatient_records_v2 (tall format)
--
-- Shape note:
--   `_v2` tables pivot the wide 10-column DGNS_CD layout to one row per
--   (patient_id, autoimmune_code) occurrence. This is the exact "10-way
--   UNION" pattern that appears in the diabetes pipeline as
--   step5_consolidate/step_2.sql's inpatient single_row_inpatient_temp
--   UNION. Agent skill-file takeaway: when a patient can have multiple
--   matching diagnoses per row, explode-then-GROUP_CONCAT is the standard
--   consolidation move.
-- =====================================================================

-- ---- autoimmune_inpatient_records (extraction, 10 DGNS cols kept wide) --

DELIMITER ;;
CREATE PROCEDURE `autoimmune_inpatient_records`()
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

	create table if not exists autoimmune_inpatient_records (
        patient_id varchar(40),
        BIRTH_DT   date,
        SRVC_BGN_DT date, SRVC_END_DT date,
        DGNS_CD_1 varchar(7), DGNS_CD_2 varchar(7), DGNS_CD_3 varchar(7),
        DGNS_CD_4 varchar(7), DGNS_CD_5 varchar(7), DGNS_CD_6 varchar(7),
        DGNS_CD_7 varchar(7), DGNS_CD_8 varchar(7), DGNS_CD_9 varchar(7),
        DGNS_CD_10 varchar(7),
        state_key int, RFRNC_YR int
    );
read_loop: loop
    create table if not exists autoimmune_inpatient_records_check (state_key int, RFRNC_YR int);
		fetch cur1 into st_key, year_num;
		if done then leave read_loop; end if;
		insert into autoimmune_inpatient_records
		(select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT,
                DGNS_CD_1, DGNS_CD_2, DGNS_CD_3, DGNS_CD_4, DGNS_CD_5,
                DGNS_CD_6, DGNS_CD_7, DGNS_CD_8, DGNS_CD_9, DGNS_CD_10,
                state_key, RFRNC_YR
         from cms_source.taf_inpatient_header t1, autoimmune_icd t2
         where state_key = st_key and rfrnc_yr = year_num
         and (t1.DGNS_CD_1 = t2.icd910 or t1.DGNS_CD_2 = t2.icd910 or
              t1.DGNS_CD_3 = t2.icd910 or t1.DGNS_CD_4 = t2.icd910 or
              t1.DGNS_CD_5 = t2.icd910 or t1.DGNS_CD_6 = t2.icd910 or
              t1.DGNS_CD_7 = t2.icd910 or t1.DGNS_CD_8 = t2.icd910 or
              t1.DGNS_CD_9 = t2.icd910 or t1.DGNS_CD_10 = t2.icd910));
        insert into autoimmune_inpatient_records_check (select st_key, year_num);
		commit;
	end loop;
end ;;
DELIMITER ;

-- ---- autoimmune_inpatient_records_v2 (pivot wide -> tall) -----------

DELIMITER ;;
CREATE PROCEDURE `autoimmune_inpatient_records_v2`()
BEGIN
create table autoimmune_inpatient_records_v2 as
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR, DGNS_CD_1 as DGNS_CD
  from autoimmune_inpatient_records where DGNS_CD_1 in (select icd910 from autoimmune_icd) union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR, DGNS_CD_2
  from autoimmune_inpatient_records where DGNS_CD_2 in (select icd910 from autoimmune_icd) union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR, DGNS_CD_3
  from autoimmune_inpatient_records where DGNS_CD_3 in (select icd910 from autoimmune_icd) union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR, DGNS_CD_4
  from autoimmune_inpatient_records where DGNS_CD_4 in (select icd910 from autoimmune_icd) union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR, DGNS_CD_5
  from autoimmune_inpatient_records where DGNS_CD_5 in (select icd910 from autoimmune_icd) union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR, DGNS_CD_6
  from autoimmune_inpatient_records where DGNS_CD_6 in (select icd910 from autoimmune_icd) union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR, DGNS_CD_7
  from autoimmune_inpatient_records where DGNS_CD_7 in (select icd910 from autoimmune_icd) union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR, DGNS_CD_8
  from autoimmune_inpatient_records where DGNS_CD_8 in (select icd910 from autoimmune_icd) union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR, DGNS_CD_9
  from autoimmune_inpatient_records where DGNS_CD_9 in (select icd910 from autoimmune_icd) union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR, DGNS_CD_10
  from autoimmune_inpatient_records where DGNS_CD_10 in (select icd910 from autoimmune_icd);
END ;;
DELIMITER ;

-- ---- autoimmune_ospatient_records (extraction, 2 DGNS cols) --------

DELIMITER ;;
CREATE PROCEDURE `autoimmune_ospatient_records`()
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

	create table if not exists autoimmune_ospatient_records (
        patient_id varchar(40),
        BIRTH_DT   date,
        SRVC_BGN_DT date, SRVC_END_DT date,
        DGNS_CD_1 varchar(7), DGNS_CD_2 varchar(7),
        state_key int, RFRNC_YR int
    );
read_loop: loop
    create table if not exists autoimmune_ospatient_records_check (state_key int, RFRNC_YR int);
		fetch cur1 into st_key, year_num;
		if done then leave read_loop; end if;
		insert into autoimmune_ospatient_records
		(select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT,
                DGNS_CD_1, DGNS_CD_2, state_key, RFRNC_YR
         from cms_source.taf_other_services_header t1, autoimmune_icd t2
         where state_key = st_key and rfrnc_yr = year_num
         and (t1.DGNS_CD_1 = t2.icd910 or t1.DGNS_CD_2 = t2.icd910));
        insert into autoimmune_ospatient_records_check (select st_key, year_num);
		commit;
	end loop;
end ;;
DELIMITER ;

-- ---- autoimmune_ospatient_records_v2 (pivot wide -> tall) ----------

DELIMITER ;;
CREATE PROCEDURE `autoimmune_ospatient_records_v2`()
BEGIN
create table autoimmune_ospatient_records_v2 as
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR, DGNS_CD_1 as DGNS_CD
  from autoimmune_ospatient_records where DGNS_CD_1 in (select icd910 from autoimmune_icd) union
select patient_id, BIRTH_DT, SRVC_BGN_DT, SRVC_END_DT, state_key, RFRNC_YR, DGNS_CD_2
  from autoimmune_ospatient_records where DGNS_CD_2 in (select icd910 from autoimmune_icd);
END ;;
DELIMITER ;

call autoimmune_inpatient_records();
call autoimmune_inpatient_records_v2();
call autoimmune_ospatient_records();
call autoimmune_ospatient_records_v2();
