-- Step 1: Widen STATE_CD (inherited as varchar(2) from All_Selected_state) so it
--         can hold the 'Ambiguous' sentinel, and add SEX_CD / ETHNCTY_CD which
--         are not populated in the claims lane.
ALTER TABLE single_row_patient_temp
MODIFY COLUMN STATE_CD VARCHAR(10),
ADD COLUMN SEX_CD VARCHAR(10),
ADD COLUMN ETHNCTY_CD VARCHAR(10);

-- Step 2: Update
UPDATE single_row_patient_temp s
JOIN (
    -- This subquery processes the logic for all patients in one pass
    SELECT 
        PATIENT_ID,
        CASE WHEN COUNT(DISTINCT STATE_CD) > 1 THEN 'Ambiguous' ELSE MAX(STATE_CD) END AS final_state,
        CASE WHEN COUNT(DISTINCT SEX_CD) > 1 THEN 'Ambiguous' ELSE MAX(SEX_CD) END AS final_sex,
        CASE WHEN COUNT(DISTINCT ETHNCTY_CD) > 1 THEN 'Ambiguous' ELSE MAX(ETHNCTY_CD) END AS final_race,
        -- Birth date remains NULL if conflicting because it is a DATE type column
        CASE WHEN COUNT(DISTINCT BIRTH_DT) > 1 THEN NULL ELSE MAX(BIRTH_DT) END AS final_birth_dt
    FROM All_Selected_state_demo
    GROUP BY PATIENT_ID
) d ON s.PATIENT_ID = d.PATIENT_ID
SET 
    s.STATE_CD = d.final_state,
    s.SEX_CD = d.final_sex,
    s.ETHNCTY_CD = d.final_race,
    s.BIRTH_DT = d.final_birth_dt;