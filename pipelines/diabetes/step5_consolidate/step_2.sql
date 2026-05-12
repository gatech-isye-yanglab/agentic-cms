-- STEP 1: Identify the 1st and 2nd diagnosis dates
-- This identifies the "Trigger" visit and the very next visit that satisfies the 2-year window
DROP TABLE IF EXISTS patient_flag_summary_GA;
CREATE TABLE patient_flag_summary_GA AS
SELECT 
    t1.patient_id,
    MIN(t1.srvc_bgn_DT) AS 1st_diab_DIAG_DT,
    MIN(t2.srvc_bgn_DT) AS 2nd_diab_DIAG_DT
FROM temp_all_in_two_years_GA t1
INNER JOIN temp_all_in_two_years_GA t2 
    ON t1.patient_id = t2.patient_id
    AND t2.srvc_bgn_DT > t1.srvc_bgn_DT
    AND t2.srvc_bgn_DT <= DATE_ADD(t1.srvc_bgn_DT, INTERVAL 2 YEAR)
WHERE t1.appears_within_2_years = 1
GROUP BY t1.patient_id;

-- STEP 2: Aggregate clinical and demographic data based on the first diagnosis date
DROP TABLE IF EXISTS single_row_patient_temp;
SET SESSION group_concat_max_len = 1000000;

CREATE TABLE single_row_patient_temp AS 
SELECT 
    t2.patient_id,
    t2.1st_diab_DIAG_DT,
    t2.2nd_diab_DIAG_DT,
    -- Pull demographic details from the first visit
    MIN(t1.state_key) AS state_key,
    MIN(t1.STATE_CD) AS STATE_CD,
    MIN(t1.BIRTH_DT) AS BIRTH_DT,
    -- Aggregate all 12 Diagnosis Columns from that specific visit date
    CONCAT_WS(',', 
        GROUP_CONCAT(t1.DIAG_CD_1), GROUP_CONCAT(t1.DIAG_CD_2),
        GROUP_CONCAT(t1.DIAG_CD_3), GROUP_CONCAT(t1.DIAG_CD_4),
        GROUP_CONCAT(t1.DIAG_CD_5), GROUP_CONCAT(t1.DIAG_CD_6),
        GROUP_CONCAT(t1.DIAG_CD_7), GROUP_CONCAT(t1.DIAG_CD_8),
        GROUP_CONCAT(t1.DIAG_CD_9), GROUP_CONCAT(t1.DIAG_CD_10),
        GROUP_CONCAT(t1.DIAG_CD_11), GROUP_CONCAT(t1.DIAG_CD_12)
    ) AS full_diag_cd_list
FROM All_Selected_state t1
INNER JOIN patient_flag_summary_GA t2 
    ON t1.patient_id = t2.patient_id 
    AND t1.srvc_bgn_DT = t2.1st_diab_DIAG_DT
GROUP BY t2.patient_id, t2.1st_diab_DIAG_DT, t2.2nd_diab_DIAG_DT;