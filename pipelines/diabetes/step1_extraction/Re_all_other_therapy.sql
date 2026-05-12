-- step 1 make a first inpatient table-- 
-- This table comes from looking at the cms_source and choosing specific columns you want from one of the tables in the cms_source, we are basically making a blank copy--
drop table if exists Re_all_other_therapy ;
CREATE TABLE Re_all_other_therapy (
  `patient_id` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `BENE_ID` varchar(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `STATE_CD` varchar(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `state_key` int DEFAULT NULL,
  `YR_NUM` int DEFAULT NULL,
  `EL_DOB` date DEFAULT NULL,
  `EL_SEX_CD` varchar(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `EL_RACE_ETHNCY_CD` varchar(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  srvc_bgn_dt date,
  srvc_end_dt date,
  `DIAG_CD_1` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `DIAG_CD_2` varchar(8) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_as_cs;

-- step 2 make the loop for first table--
-- What this loop does is search up specific DIAGNOSIS codes repeat searches through each diagnosis column--
--  dropping the procedure if it exists already

 -- don't ask, just make sure this line is there
DELIMITER $$  
DROP PROCEDURE IF EXISTS Re_all_other_therapy_loop;
CREATE PROCEDURE `Re_all_other_therapy_loop`()
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
-- this is where you insert your new columns into your existening columns from first table--
-- make sure everything lines up and is in the correct order, spelled correctly (captilization)--
		insert into Re_all_other_therapy
			(patient_id, BENE_ID, STATE_CD, state_key, YR_NUM, EL_DOB, EL_SEX_CD, EL_RACE_ETHNCY_CD,  srvc_bgn_dt,
  srvc_end_dt, DIAG_CD_1, DIAG_CD_2)
			select
				patient_id, 
                BENE_ID,
				st_cd as STATE_CD,
                st_key as state_key,
				year_num as YR_NUM,
                EL_DOB,
                EL_SEX_CD, 
                EL_RACE_ETHNCY_CD,
				srvc_bgn_dt,
				srvc_end_dt,
				DIAG_CD_1,
                DIAG_CD_2
			from cms_source.other_therapy
			where state_key = st_key
			and yr_num = year_num
			and (
				DIAG_CD_1 in (select codes from icd_9_cm)
				OR DIAG_CD_2 in (select codes from icd_9_cm)
                OR DIAG_CD_1 like 'E08%' OR DIAG_CD_1 like 'E09%' OR DIAG_CD_1 like 'E11%' OR DIAG_CD_1 like 'E13%' OR DIAG_CD_1 like 'O241%' OR DIAG_CD_1 like 'O243%' OR DIAG_CD_1 like 'O248%'
                OR DIAG_CD_2 like 'E08%' OR DIAG_CD_2 like 'E09%' OR DIAG_CD_2 like 'E11%' OR DIAG_CD_2 like 'E13%' OR DIAG_CD_2 like 'O241%' OR DIAG_CD_2 like 'O243%' OR DIAG_CD_2 like 'O248%'
           );

	end loop;

	close cur1; 
	
end$$			-- once again, don't ask
DELIMITER ;		-- once again, don't ask

call Re_all_other_therapy_loop();
	