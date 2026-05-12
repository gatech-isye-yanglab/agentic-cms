-- step 1: Create the filtered state demographic table
drop table if exists All_Selected_state_demo;
Create table All_Selected_state_demo(
  `PATIENT_ID` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `BENE_ID` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `STATE_CD` varchar(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `STATE_KEY` int DEFAULT NULL,
  `YR_NUM` int DEFAULT NULL,
  `BIRTH_DT` date DEFAULT NULL,
  `AGE` int DEFAULT NULL,
  `SEX_CD` varchar(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `ETHNCTY_CD` varchar(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DEATH_DT` date DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_as_cs;

-- step 2: Insert data from the combined demographic source for specific states
INSERT INTO All_Selected_state_demo (
    PATIENT_ID, 
    BENE_ID, 
    STATE_CD, 
    STATE_KEY, 
    YR_NUM, 
    BIRTH_DT, 
    AGE, 
    SEX_CD, 
    ETHNCTY_CD, 
    DEATH_DT
)
SELECT
    PATIENT_ID, 
    BENE_ID, 
    STATE_CD, 
    STATE_KEY, 
    YR_NUM, 
    BIRTH_DT, 
    AGE, 
    SEX_CD, 
    ETHNCTY_CD, 
    DEATH_DT
FROM all_combine_demo
WHERE STATE_CD IN ('AL', 'FL', 'GA', 'MS', 'NC', 'SC', 'TN');