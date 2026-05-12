-- Step 1: Create the main personal summary table
DROP TABLE IF EXISTS Re_personal_summary;
CREATE TABLE Re_personal_summary (
  `PATIENT_ID` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `MSIS_ID` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `STATE_CD` varchar(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `state_key` int DEFAULT NULL,
  `year_num` int DEFAULT NULL,
  `EL_DOB` date DEFAULT NULL,
  `AGE` int DEFAULT NULL,
  `EL_SEX_CD` varchar(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `EL_RACE_ETHNCY_CD` varchar(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_as_cs;

-- Step 2: Create the loop procedure
DELIMITER $$  
DROP PROCEDURE IF EXISTS Re_personal_summary_loop;
CREATE PROCEDURE `Re_personal_summary_loop`()
BEGIN
    DECLARE st_key INT;
    DECLARE st_cd VARCHAR(2);
    DECLARE y_num INT; 
    DECLARE done BOOLEAN DEFAULT 0;
    
    DECLARE cur1 CURSOR FOR 
        SELECT sc.state_key, sc.state_code, dy.year_num
        FROM cms_source.state_codes sc, cms_source.data_years dy
        ORDER BY sc.state_code, dy.year_num;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    OPEN cur1;

read_loop: LOOP
        FETCH cur1 INTO st_key, st_cd, y_num;
        IF done THEN
            LEAVE read_loop;
        END IF;

        INSERT INTO Re_personal_summary
            (PATIENT_ID, MSIS_ID, STATE_CD, state_key, year_num, EL_DOB, AGE, EL_SEX_CD, EL_RACE_ETHNCY_CD)
        SELECT 
            patient_id, 
            MSIS_ID, 
            st_cd as STATE_CD, 
            st_key as state_key, 
            y_num as year_num, 
            EL_DOB, 
            AGE, 
            EL_SEX_CD, 
            EL_RACE_ETHNCY_CD
        FROM cms_source.personal_summary
        WHERE state_key = st_key
        AND MAX_YR_DT = y_num;

    END LOOP;
    CLOSE cur1; 
END$$
DELIMITER ;

-- Step 3: Run the procedure
CALL Re_personal_summary_loop();