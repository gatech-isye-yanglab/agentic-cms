-- =====================================================================
-- Step 5 — Final analytical tables (survival analysis inputs)
--
-- Source: gold-standard SQL (TAF-era cohort)
--   chemo_table_final        — lines 1150-1181 (+ immuno_table_final in same proc)
--   immuno_table_therapy     — lines 2183-2227 (per-drug subgroups NO/PK/AT/DI)
--   immuno_table_dm          — lines 2087-2103
--   immuno_table_hypo        — lines 2119-2135
--   immuno_table_ra          — lines 2151-2166
--   immuno_table_thyro       — lines 2244-2260
-- Owner:  gold-standard SQL author
--
-- Output schema (chemo_table_final / immuno_table_final):
--   patient_id, sex_cd, RACE_ETHNCTY_CD, utilization, sickness, age,
--   days, censoring, treatment, autoimmune_code
--
-- Column definitions:
--   days       = time from first treatment to first autoimmune event OR
--                to last observation (if no event). The "time" variable
--                for Kaplan-Meier / Cox regression.
--   censoring  = 1 if no autoimmune event (censored at last observation),
--                0 if event observed. (Note: v4/v6 already filtered to
--                only keep patients whose autoimmune event post-dates
--                therapy; this field encodes whether they had one at all.)
--   treatment  = 0 for chemo arm, 1 for immuno arm.
--
-- Two UNIONs per final table:
--   - 2017+ TAF-era results (lung_chemo_autoimmune_patient_v7 /
--                            lung_immuno_autoimmune_patient_v7)
--   - 2016-era results from <scratch_db>.Single_Row_Table, wrapped in
--     chemo_table_2016_v3 / immuno_table_2016_v3 (the parallel TAF-2016
--     pipeline that uses regex-based HCPCS matching to catch
--     pre-approval C-codes).
--
-- This is the merge point where the 2017+ pipeline and the TAF-2016
-- parallel pipeline come together into one analytical row per patient.
-- =====================================================================

-- ---- chemo_table_final / immuno_table_final -----------------------

DELIMITER ;;
CREATE PROCEDURE `chemo_table_final`()
BEGIN
drop table if exists chemo_table_final;
create table chemo_table_final as
select patient_id, sex_cd, RACE_ETHNCTY_CD, utilization, sickness,
       round(datediff(first_lung_dt, BIRTH_DT)/365) as age,
       if(first_autoimmune_dt is null,
          datediff(last_record_dt, first_chemo_dt),
          datediff(first_autoimmune_dt, first_chemo_dt)) as days,
       if(first_autoimmune_dt is null, 1, 0) as censoring,
       0 as treatment,
       autoimmune_code
from lung_chemo_autoimmune_patient_v7;
-- 2016-era UNION with <scratch_db>.chemo_table_2016_v3 is no longer needed:
-- the main TAF pipeline now covers 2016+ natively (step1_extraction/*.sql
-- filter on year_num >= 2016). 2016 patients flow through v3..v7 the
-- same way 2017+ patients do; lung_chemo_autoimmune_patient_v7 already
-- contains them.

drop table if exists immuno_table_final;
create table immuno_table_final as
select patient_id, sex_cd, RACE_ETHNCTY_CD, utilization, sickness,
       round(datediff(first_lung_dt, BIRTH_DT)/365) as age,
       if(first_autoimmune_dt is null,
          datediff(last_record_dt, first_immuno_dt),
          datediff(first_autoimmune_dt, first_immuno_dt)) as days,
       if(first_autoimmune_dt is null, 1, 0) as censoring,
       1 as treatment,
       autoimmune_code
from lung_immuno_autoimmune_patient_v7;
-- 2016-era UNION unnecessary — see comment above; 2016 TAF data is in v7.

-- Ambiguity patches (min != max in upstream concat) --
update immuno_table_final set RACE_ETHNCTY_CD = 'U'
  where RACE_ETHNCTY_CD in ('ambiguous','Ambiguous','0') or RACE_ETHNCTY_CD is null;
update chemo_table_final  set RACE_ETHNCTY_CD = 'U'
  where RACE_ETHNCTY_CD in ('ambiguous','Ambiguous','0') or RACE_ETHNCTY_CD is null;
update immuno_table_final set sex_cd = 'U'
  where sex_cd in ('ambiguous','Ambiguous') or sex_cd is null;
update chemo_table_final  set sex_cd = 'U'
  where sex_cd in ('ambiguous','Ambiguous') or sex_cd is null;
update chemo_table_final  set age = -1 where age is null;
update immuno_table_final set age = -1 where age is null;
END ;;
DELIMITER ;

-- ---- immuno_table_therapy: drug-level subgroups -------------------
--
-- Per-drug survival tables: the published thesis chapter reports the headline
-- result across all immunotherapy (HR ≈ 2.4), but also 4 drug-specific
-- HRs (Nivolumab, Pembrolizumab, Atezolizumab, Ipilimumab). Those are
-- built here by filtering chemo_table_final / immuno_table_final on
-- cpt_cd LIKE '%<drug-code>%'.

DELIMITER ;;
CREATE PROCEDURE `immuno_table_therapy`()
BEGIN
-- NO = Nivolumab (Opdivo) — PD-1
create table immuno_table_NO as
select patient_id, sex_cd, RACE_ETHNCTY_CD, utilization, sickness,
       round(datediff(first_lung_dt, BIRTH_DT)/365) as age,
       autoimmune_code,
       if(first_autoimmune_dt is null,
          datediff(last_record_dt, first_immuno_dt),
          datediff(first_autoimmune_dt, first_immuno_dt)) as days,
       if(first_autoimmune_dt is null, 1, 0) as censoring,
       1 as treatment
from lung_immuno_autoimmune_patient_v7
where cpt_cd like '%C9453%' or cpt_cd like '%J9299%';

-- PK = Pembrolizumab (Keytruda) — PD-1
create table immuno_table_PK as
select patient_id, sex_cd, RACE_ETHNCTY_CD, utilization, sickness,
       round(datediff(first_lung_dt, BIRTH_DT)/365) as age,
       autoimmune_code,
       if(first_autoimmune_dt is null,
          datediff(last_record_dt, first_immuno_dt),
          datediff(first_autoimmune_dt, first_immuno_dt)) as days,
       if(first_autoimmune_dt is null, 1, 0) as censoring,
       1 as treatment
from lung_immuno_autoimmune_patient_v7
where cpt_cd like '%C9027%' or cpt_cd like '%J9271%';

-- AT = Atezolizumab (Tecentriq) — PD-L1. Ported from <scratch_db>.sql:2207.
create table immuno_table_AT as
select patient_id, sex_cd, RACE_ETHNCTY_CD, utilization, sickness,
       round(datediff(first_lung_dt, BIRTH_DT)/365) as age,
       autoimmune_code,
       if(first_autoimmune_dt is null,
          datediff(last_record_dt, first_immuno_dt),
          datediff(first_autoimmune_dt, first_immuno_dt)) as days,
       if(first_autoimmune_dt is null, 1, 0) as censoring,
       1 as treatment
from lung_immuno_autoimmune_patient_v7
where cpt_cd like '%C9483%' or cpt_cd like '%J9022%';

-- DI = Durvalumab (Imfinzi) — PD-L1. Ported from <scratch_db>.sql:2218.
-- NOTE: the gold standard's original filter was `cpt_cd like '%C9492%'` only; that
-- appears to conflict with the CMS HCPCS mapping where C9492 is the
-- Avelumab pre-approval code (per reference/immuno_hcpcs_legacy_claims.md).
-- Using J9173 (permanent Durvalumab J-code) + C9491 (Durvalumab
-- pre-approval) instead, which aligns with the a legacy commercial-claims study reference. If
-- strict reproduction of the gold standard's original filter is required, swap back
-- to `cpt_cd like '%C9492%'`.
create table immuno_table_DI as
select patient_id, sex_cd, RACE_ETHNCTY_CD, utilization, sickness,
       round(datediff(first_lung_dt, BIRTH_DT)/365) as age,
       autoimmune_code,
       if(first_autoimmune_dt is null,
          datediff(last_record_dt, first_immuno_dt),
          datediff(first_autoimmune_dt, first_immuno_dt)) as days,
       if(first_autoimmune_dt is null, 1, 0) as censoring,
       1 as treatment
from lung_immuno_autoimmune_patient_v7
where cpt_cd like '%J9173%' or cpt_cd like '%C9491%';

-- IP = Ipilimumab (Yervoy) — CTLA-4. Not in the TAF-era cohort SQL's immuno_table_therapy
-- but the HCPCS codes are in our immuno_cpt_codes reference table (J9228
-- permanent, C9284 pre-approval). Added for completeness — the published thesis
-- reports per-drug HRs for Nivolumab/Pembrolizumab/Atezolizumab/Ipilimumab.
create table immuno_table_IP as
select patient_id, sex_cd, RACE_ETHNCTY_CD, utilization, sickness,
       round(datediff(first_lung_dt, BIRTH_DT)/365) as age,
       autoimmune_code,
       if(first_autoimmune_dt is null,
          datediff(last_record_dt, first_immuno_dt),
          datediff(first_autoimmune_dt, first_immuno_dt)) as days,
       if(first_autoimmune_dt is null, 1, 0) as censoring,
       1 as treatment
from lung_immuno_autoimmune_patient_v7
where cpt_cd like '%J9228%' or cpt_cd like '%C9284%';

-- AV = Avelumab (Bavencio) — PD-L1. Included for symmetry; lung-cancer
-- volume is small per the a legacy commercial-claims study reference but the HCPCS codes are in
-- our reference table (J9023 permanent, C9492 pre-approval). On the
-- CMS-pipeline sidethe gold-standard authordidn't report an Avelumab-specific HR, so this
-- table exists but isn't cited in the published thesis chapter.
create table immuno_table_AV as
select patient_id, sex_cd, RACE_ETHNCTY_CD, utilization, sickness,
       round(datediff(first_lung_dt, BIRTH_DT)/365) as age,
       autoimmune_code,
       if(first_autoimmune_dt is null,
          datediff(last_record_dt, first_immuno_dt),
          datediff(first_autoimmune_dt, first_immuno_dt)) as days,
       if(first_autoimmune_dt is null, 1, 0) as censoring,
       1 as treatment
from lung_immuno_autoimmune_patient_v7
where cpt_cd like '%J9023%' or cpt_cd like '%C9492%';
END ;;
DELIMITER ;

-- ---- disease-specific subgroups: immuno_table_dm / hypo / ra -----
--
-- For each disease sub-slice (hypothyroidism, thyroiditis, RA, myalgia,
-- diabetes mellitus), build a *_table_dm / *_table_hypo / *_table_ra
-- by filtering on whether autoimmune_code falls in the per-disease slice
-- of autoimmune_icd (autoimmune_icd_dm, autoimmune_icd_hypo, etc.).

-- All four per-disease procedures follow the same template:
--   1. For each patient, flag whether their autoimmune_code (comma-
--      separated GROUP_CONCAT string) contains any code in the relevant
--      `autoimmune_icd_<disease>` view.
--   2. A patient can have up to 2 comma-separated codes in
--      autoimmune_code (from the 2-column outpatient header + the
--      pivoted inpatient rows); check positions 1 and 2 explicitly.
--   3. NULL autoimmune_code → not a case for this disease → flag = 0.
--
-- The flag column is named after the disease so downstream Cox models
-- can do `fit coxph(Surv(days, censoring) ~ treatment + ..., data=immuno_table_dm)`.

DELIMITER ;;
CREATE PROCEDURE `immuno_table_dm`()
BEGIN
-- Type-1 diabetes mellitus. Ported from <scratch_db>.sql:2087.
create table immuno_table_dm as
select t1.*,
       if(autoimmune_code not like '%,%',
          autoimmune_code in (select icd910 from autoimmune_icd_dm),
          (substring_index(autoimmune_code, ',', 1) in (select icd910 from autoimmune_icd_dm) or
           substring_index(autoimmune_code, ',', 2) in (select icd910 from autoimmune_icd_dm))
       ) as dm
from immuno_table_final t1;
update immuno_table_dm set dm = 0 where dm is null;

create table chemo_table_dm as
select t1.*,
       if(autoimmune_code not like '%,%',
          autoimmune_code in (select icd910 from autoimmune_icd_dm),
          (substring_index(autoimmune_code, ',', 1) in (select icd910 from autoimmune_icd_dm) or
           substring_index(autoimmune_code, ',', 2) in (select icd910 from autoimmune_icd_dm))
       ) as dm
from chemo_table_final t1;
update chemo_table_dm set dm = 0 where dm is null;
END ;;
DELIMITER ;

DELIMITER ;;
CREATE PROCEDURE `immuno_table_hypo`()
BEGIN
-- Hypothyroidism. Ported from <scratch_db>.sql:2119.
create table immuno_table_hypo as
select t1.*,
       if(autoimmune_code not like '%,%',
          autoimmune_code in (select icd910 from autoimmune_icd_hypo),
          (substring_index(autoimmune_code, ',', 1) in (select icd910 from autoimmune_icd_hypo) or
           substring_index(autoimmune_code, ',', 2) in (select icd910 from autoimmune_icd_hypo))
       ) as hypo
from immuno_table_final t1;
update immuno_table_hypo set hypo = 0 where hypo is null;

create table chemo_table_hypo as
select t1.*,
       if(autoimmune_code not like '%,%',
          autoimmune_code in (select icd910 from autoimmune_icd_hypo),
          (substring_index(autoimmune_code, ',', 1) in (select icd910 from autoimmune_icd_hypo) or
           substring_index(autoimmune_code, ',', 2) in (select icd910 from autoimmune_icd_hypo))
       ) as hypo
from chemo_table_final t1;
update chemo_table_hypo set hypo = 0 where hypo is null;
END ;;
DELIMITER ;

DELIMITER ;;
CREATE PROCEDURE `immuno_table_ra`()
BEGIN
-- Rheumatoid arthritis. Ported from <scratch_db>.sql:2151.
create table immuno_table_ra as
select t1.*,
       if(autoimmune_code not like '%,%',
          autoimmune_code in (select icd910 from autoimmune_icd_ra),
          (substring_index(autoimmune_code, ',', 1) in (select icd910 from autoimmune_icd_ra) or
           substring_index(autoimmune_code, ',', 2) in (select icd910 from autoimmune_icd_ra))
       ) as ra
from immuno_table_final t1;
update immuno_table_ra set ra = 0 where ra is null;

create table chemo_table_ra as
select t1.*,
       if(autoimmune_code not like '%,%',
          autoimmune_code in (select icd910 from autoimmune_icd_ra),
          (substring_index(autoimmune_code, ',', 1) in (select icd910 from autoimmune_icd_ra) or
           substring_index(autoimmune_code, ',', 2) in (select icd910 from autoimmune_icd_ra))
       ) as ra
from chemo_table_final t1;
update chemo_table_ra set ra = 0 where ra is null;
END ;;
DELIMITER ;

DELIMITER ;;
CREATE PROCEDURE `immuno_table_thyro`()
BEGIN
-- Thyroiditis. Ported from <scratch_db>.sql:2244. Uses the `autoimmune_icd_thyro`
-- view alias (same as autoimmune_icd_thyroiditis).
create table immuno_table_thyro as
select t1.*,
       if(autoimmune_code not like '%,%',
          autoimmune_code in (select icd910 from autoimmune_icd_thyro),
          (substring_index(autoimmune_code, ',', 1) in (select icd910 from autoimmune_icd_thyro) or
           substring_index(autoimmune_code, ',', 2) in (select icd910 from autoimmune_icd_thyro))
       ) as thyro
from immuno_table_final t1;
update immuno_table_thyro set thyro = 0 where thyro is null;

create table chemo_table_thyro as
select t1.*,
       if(autoimmune_code not like '%,%',
          autoimmune_code in (select icd910 from autoimmune_icd_thyro),
          (substring_index(autoimmune_code, ',', 1) in (select icd910 from autoimmune_icd_thyro) or
           substring_index(autoimmune_code, ',', 2) in (select icd910 from autoimmune_icd_thyro))
       ) as thyro
from chemo_table_final t1;
update chemo_table_thyro set thyro = 0 where thyro is null;
END ;;
DELIMITER ;

call chemo_table_final();
call immuno_table_therapy();
call immuno_table_dm();
call immuno_table_hypo();
call immuno_table_ra();
call immuno_table_thyro();
