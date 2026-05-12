-- This is the same from STEP1 in 101 foldler, just with a different table as an example--
-- step 1 make the taf table--

DROP table IF EXISTS Re_All_taf_inpatient_header;
CREATE TABLE Re_All_taf_inpatient_header (
  `PATIENT_ID` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `BENE_ID` varchar(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `STATE_CD` varchar(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `STATE_KEY` int DEFAULT NULL,
  `RFRNC_YR` int DEFAULT NULL,
  `BIRTH_DT` date DEFAULT NULL,
   srvc_bgn_dt date,
   srvc_end_dt date,
  `DGNS_CD_1` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DGNS_CD_2` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DGNS_CD_3` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DGNS_CD_4` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DGNS_CD_5` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DGNS_CD_6` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DGNS_CD_7` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DGNS_CD_8` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DGNS_CD_9` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DGNS_CD_10` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DGNS_CD_11` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DGNS_CD_12` varchar(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_as_cs;


-- step 2 make the taf loop--
--  drop procedure demo_loop;  -- (in your scratch DB)
DROP PROCEDURE IF EXISTS Re_All_taf_inpatient_header;
 -- don't ask, just make sure this line is there
DELIMITER $$  
CREATE PROCEDURE `Re_All_taf_inpatient_header`()
begin
	-- variables must be declared before the cursor.
	declare st_key int;				-- variable for the state_key
	declare st_cd varchar(2);		-- variable for the state_code
	declare year_num int; 			-- variable for the year number
    declare done boolean default 0;
	
--  This is going to get a list of all state_keys to iterate over
--  This gets all states
declare cur1 cursor for 
			select sc.state_key, sc.state_code, dy.year_num
            from cms_source.state_codes sc, cms_source.data_years dy
			order by sc.state_code, dy.year_num;
    declare continue handler for not found set done = 1;   -- looks for the end of the result set
 
	-- this opens the cursor.  ( It runs the query )   
    open cur1;

read_loop:	loop
    
		-- this brings the first ( next ) row of data into the listed variables.
		fetch cur1 into st_key, st_cd, year_num;
        
		if done then
			leave read_loop;
		end if;

		insert into Re_All_taf_inpatient_header
			(PATIENT_ID, BENE_ID, STATE_CD, STATE_KEY, RFRNC_YR, BIRTH_DT,  srvc_bgn_dt,
  srvc_end_dt, DGNS_CD_1, DGNS_CD_2, DGNS_CD_3, DGNS_CD_4, DGNS_CD_5, DGNS_CD_6, DGNS_CD_7, DGNS_CD_8, DGNS_CD_9, DGNS_CD_10, DGNS_CD_11, DGNS_CD_12)
			select
				PATIENT_ID, 
                BENE_ID,
				state_cd as STATE_CD,
                state_key as STATE_KEY,
				year_num as RFRNC_YR,
                BIRTH_DT,
				srvc_bgn_dt,
				srvc_end_dt,
				DGNS_CD_1,
				DGNS_CD_2,
				DGNS_CD_3,
				DGNS_CD_4,
				DGNS_CD_5,
				DGNS_CD_6,
				DGNS_CD_7,
				DGNS_CD_8,
				DGNS_CD_9,
				DGNS_CD_10,
				DGNS_CD_11,
				DGNS_CD_12
			from cms_source.taf_inpatient_header
			where STATE_KEY = st_key
			and RFRNC_YR = year_num
			and (DGNS_CD_1 in (select codes from icd_9_cm)
				OR DGNS_CD_2 in (select codes from icd_9_cm)
                OR DGNS_CD_3 in (select codes from icd_9_cm)
                OR DGNS_CD_4 in (select codes from icd_9_cm)
                OR DGNS_CD_5 in (select codes from icd_9_cm)
                OR DGNS_CD_6 in (select codes from icd_9_cm)
                OR DGNS_CD_7 in (select codes from icd_9_cm)
                OR DGNS_CD_8 in (select codes from icd_9_cm)
                OR DGNS_CD_9 in (select codes from icd_9_cm)
                OR DGNS_CD_10 in (select codes from icd_9_cm)
                OR DGNS_CD_11 in (select codes from icd_9_cm)
                OR DGNS_CD_12 in (select codes from icd_9_cm)
				OR DGNS_CD_1 like 'E08%' OR DGNS_CD_1 like 'E09%' OR DGNS_CD_1 like 'E11%' OR DGNS_CD_1 like 'E13%' OR DGNS_CD_1 like 'O241%' OR DGNS_CD_1 like 'O243%' OR DGNS_CD_1 like 'O248%'
                OR DGNS_CD_2 like 'E08%' OR DGNS_CD_2 like 'E09%' OR DGNS_CD_2 like 'E11%' OR DGNS_CD_2 like 'E13%' OR DGNS_CD_2 like 'O241%' OR DGNS_CD_2 like 'O243%' OR DGNS_CD_2 like 'O248%'
                OR DGNS_CD_3 like 'E08%' OR DGNS_CD_3 like 'E09%' OR DGNS_CD_3 like 'E11%' OR DGNS_CD_3 like 'E13%' OR DGNS_CD_3 like 'O241%' OR DGNS_CD_3 like 'O243%' OR DGNS_CD_3 like 'O248%'
                OR DGNS_CD_4 like 'E08%' OR DGNS_CD_4 like 'E09%' OR DGNS_CD_4 like 'E11%' OR DGNS_CD_4 like 'E13%' OR DGNS_CD_4 like 'O241%' OR DGNS_CD_4 like 'O243%' OR DGNS_CD_4 like 'O248%'
                OR DGNS_CD_5 like 'E08%' OR DGNS_CD_5 like 'E09%' OR DGNS_CD_5 like 'E11%' OR DGNS_CD_5 like 'E13%' OR DGNS_CD_5 like 'O241%' OR DGNS_CD_5 like 'O243%' OR DGNS_CD_5 like 'O248%'
                OR DGNS_CD_6 like 'E08%' OR DGNS_CD_6 like 'E09%' OR DGNS_CD_6 like 'E11%' OR DGNS_CD_6 like 'E13%' OR DGNS_CD_6 like 'O241%' OR DGNS_CD_6 like 'O243%' OR DGNS_CD_6 like 'O248%'
                OR DGNS_CD_7 like 'E08%' OR DGNS_CD_7 like 'E09%' OR DGNS_CD_7 like 'E11%' OR DGNS_CD_7 like 'E13%' OR DGNS_CD_7 like 'O241%' OR DGNS_CD_7 like 'O243%' OR DGNS_CD_7 like 'O248%'
                OR DGNS_CD_8 like 'E08%' OR DGNS_CD_8 like 'E09%' OR DGNS_CD_8 like 'E11%' OR DGNS_CD_8 like 'E13%' OR DGNS_CD_8 like 'O241%' OR DGNS_CD_8 like 'O243%' OR DGNS_CD_8 like 'O248%'
                OR DGNS_CD_9 like 'E08%' OR DGNS_CD_9 like 'E09%' OR DGNS_CD_9 like 'E11%' OR DGNS_CD_9 like 'E13%' OR DGNS_CD_9 like 'O241%' OR DGNS_CD_9 like 'O243%' OR DGNS_CD_9 like 'O248%'
				OR DGNS_CD_10 like 'E08%' OR DGNS_CD_10 like 'E09%' OR DGNS_CD_10 like 'E11%' OR DGNS_CD_10 like 'E13%' OR DGNS_CD_10 like 'O241%' OR DGNS_CD_10 like 'O243%' OR DGNS_CD_10 like 'O248%'
				OR DGNS_CD_11 like 'E08%' OR DGNS_CD_11 like 'E09%' OR DGNS_CD_11 like 'E11%' OR DGNS_CD_11 like 'E13%' OR DGNS_CD_11 like 'O241%' OR DGNS_CD_11 like 'O243%' OR DGNS_CD_11 like 'O248%'
				OR DGNS_CD_12 like 'E08%' OR DGNS_CD_12 like 'E09%' OR DGNS_CD_12 like 'E11%' OR DGNS_CD_12 like 'E13%' OR DGNS_CD_12 like 'O241%' OR DGNS_CD_12 like 'O243%' OR DGNS_CD_12 like 'O248%');
                
                
        commit;

	end loop;

	close cur1; 
	
end$$			-- once again, don't ask
DELIMITER ;		-- once again, don't ask

call Re_All_taf_inpatient_header();