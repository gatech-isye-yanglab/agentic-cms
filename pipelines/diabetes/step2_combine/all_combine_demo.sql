-- step 1 make the combined demo table--
DROP TABLE IF EXISTS all_combine_demo;
CREATE TABLE all_combine_demo (
  `PATIENT_ID` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `BENE_ID` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL, -- Unified BENE_ID/MSIS_ID
  `STATE_CD` varchar(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `STATE_KEY` int DEFAULT NULL,
  `YR_NUM` int DEFAULT NULL, -- Unified year column
  `BIRTH_DT` date DEFAULT NULL, -- Unified EL_DOB/BIRTH_DT
  `AGE` int DEFAULT NULL,
  `SEX_CD` varchar(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `ETHNCTY_CD` varchar(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DEATH_DT` date DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_as_cs;

-- step 2 combine all 3 demographic tables into the created combined table --

-- 1. Insert from Re_taf_demog_elig_base
INSERT INTO all_combine_demo (
    PATIENT_ID, BENE_ID, STATE_CD, STATE_KEY, YR_NUM, BIRTH_DT, AGE, SEX_CD, ETHNCTY_CD, DEATH_DT
)
SELECT
    PATIENT_ID, BENE_ID, STATE_CD, STATE_KEY, RFRNC_YR, BIRTH_DT, AGE, SEX_CD, RACE_ETHNCTY_CD, DEATH_DT
FROM Re_taf_demog_elig_base;

-- 2. Insert from Re_personal_summary
INSERT INTO all_combine_demo (
    PATIENT_ID, BENE_ID, STATE_CD, STATE_KEY, YR_NUM, BIRTH_DT, AGE, SEX_CD, ETHNCTY_CD
)
SELECT
    PATIENT_ID, MSIS_ID, STATE_CD, state_key, year_num, EL_DOB, AGE, EL_SEX_CD, EL_RACE_ETHNCY_CD
FROM Re_personal_summary;

-- 3. Insert from Re_personal_summary1315
INSERT INTO all_combine_demo (
    PATIENT_ID, BENE_ID, STATE_CD, STATE_KEY, YR_NUM, BIRTH_DT, AGE, SEX_CD, ETHNCTY_CD
)
SELECT
    PATIENT_ID, MSIS_ID, STATE_CD, state_key, year_num, EL_DOB, AGE, EL_SEX_CD, EL_RACE_ETHNCY_CD
FROM Re_personal_summary1315;