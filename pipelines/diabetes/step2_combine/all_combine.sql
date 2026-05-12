-- step 1 make the combined table--
-- has every single column from all the tables you have made prior--
Drop table if exists all_combine;
CREATE TABLE all_combine(
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



-- step 2 combined all 3 other tables into the created combined table ^^^--
-- make sure the insert into columns are still in the correct order of placement--
INSERT INTO all_combine (
patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, DIAG_CD_2, DIAG_CD_3, DIAG_CD_4, DIAG_CD_5, DIAG_CD_6, DIAG_CD_7, DIAG_CD_8, DIAG_CD_9)
SELECT
patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, DIAG_CD_2, DIAG_CD_3, DIAG_CD_4, DIAG_CD_5, DIAG_CD_6, DIAG_CD_7, DIAG_CD_8, DIAG_CD_9
FROM Re_all_inpatient;

INSERT INTO all_combine (
patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, DIAG_CD_2, DIAG_CD_3, DIAG_CD_4, DIAG_CD_5, DIAG_CD_6, DIAG_CD_7, DIAG_CD_8, DIAG_CD_9)
SELECT
patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, DIAG_CD_2, DIAG_CD_3, DIAG_CD_4, DIAG_CD_5, DIAG_CD_6, DIAG_CD_7, DIAG_CD_8, DIAG_CD_9
FROM Re_all_inpatient1315;

INSERT INTO all_combine (
patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, srvc_bgn_dt, srvc_end_dt, Diag_CD_1, Diag_CD_2)
SELECT
PATIENT_ID, BENE_ID, STATE_CD, STATE_KEY, RFRNC_YR, srvc_bgn_dt, srvc_end_dt, DGNS_CD_1, DGNS_CD_2
FROM Re_All_other_services_header;

INSERT INTO all_combine (
patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, DIAG_CD_2)
SELECT
patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, DIAG_CD_2
FROM Re_all_other_therapy;

INSERT INTO all_combine (
patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, DIAG_CD_2)
SELECT
patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, DIAG_CD_2
FROM Re_all_other_therapy1315;

INSERT INTO all_combine (
patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, srvc_bgn_dt, srvc_end_dt, DIAG_CD_1, DIAG_CD_2, DIAG_CD_3, DIAG_CD_4, DIAG_CD_5, DIAG_CD_6, DIAG_CD_7, DIAG_CD_8,DIAG_CD_9, DIAG_CD_10 ,DIAG_CD_11 ,DIAG_CD_12)
SELECT
patient_id, BENE_ID, STATE_CD, state_key, RFRNC_YR, srvc_bgn_dt, srvc_end_dt, DGNS_CD_1, DGNS_CD_2, DGNS_CD_3, DGNS_CD_4, DGNS_CD_5, DGNS_CD_6, DGNS_CD_7, DGNS_CD_8, DGNS_CD_9, DGNS_CD_10, DGNS_CD_11, DGNS_CD_12
FROM Re_All_taf_inpatient_header;
