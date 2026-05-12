drop table if exists All_Selected_state;
Create table All_Selected_state(
`PATIENT_ID` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `BENE_ID` varchar(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `STATE_CD` varchar(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `STATE_KEY` int DEFAULT NULL,
  `YR_NUM` int DEFAULT NULL,
  `BIRTH_DT` date DEFAULT NULL,
   srvc_bgn_dt date,
   srvc_end_dt date,
  `DIAG_CD_1` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DIAG_CD_2` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DIAG_CD_3` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DIAG_CD_4` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DIAG_CD_5` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DIAG_CD_6` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DIAG_CD_7` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DIAG_CD_8` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DIAG_CD_9` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DIAG_CD_10` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DIAG_CD_11` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DIAG_CD_12` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_as_cs;

INSERT INTO All_Selected_state (
patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, DIAG_CD_2, DIAG_CD_3, DIAG_CD_4, DIAG_CD_5, DIAG_CD_6, DIAG_CD_7, DIAG_CD_8,DIAG_CD_9, DIAG_CD_10 ,DIAG_CD_11 ,DIAG_CD_12)
SELECT
patient_id, BENE_ID, STATE_CD, state_key, YR_num, srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, DIAG_CD_2, DIAG_CD_3, DIAG_CD_4, DIAG_CD_5, DIAG_CD_6, DIAG_CD_7, DIAG_CD_8, DIAG_CD_9, DIAG_CD_10 ,DIAG_CD_11 ,DIAG_CD_12
FROM all_combine
where state_cd ='AL'
or state_cd='FL'
or state_cd='GA'
or state_cd='MS'
or state_cd='NC'
or state_cd='SC'
or state_cd='TN'

