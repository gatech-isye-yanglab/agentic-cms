-- Step 1: Create the demographic summary table
DROP TABLE IF EXISTS Re_taf_demog_elig_base;
CREATE TABLE Re_taf_demog_elig_base (
  `PATIENT_ID` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `BENE_ID` varchar(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `STATE_CD` varchar(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs DEFAULT NULL,
  `STATE_KEY` int DEFAULT NULL,
  `RFRNC_YR` int DEFAULT NULL,
  `BIRTH_DT` date DEFAULT NULL,
  `AGE` int DEFAULT NULL,
  `AGE_GRP_CD` varchar(2) DEFAULT NULL,
  `DEATH_DT` date DEFAULT NULL,
  `SEX_CD` varchar(1) DEFAULT NULL,
  `ETHNCTY_CD` varchar(1) DEFAULT NULL,
  `RACE_ETHNCTY_CD` varchar(1) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_as_cs;

-- don't ask, just make sure this line is there
DELIMITER $$  
DROP PROCEDURE IF EXISTS Re_taf_demog_loop;
CREATE PROCEDURE `Re_taf_demog_loop`()
begin
	-- variables must be declared before the cursor.
    declare st_key int;				-- variable for the state_key
	declare st_cd varchar(2);		-- variable for the state_code
	declare year_num int; 			-- variable for the year number
    declare done boolean default 0;
	
--  This gets all states and years to iterate over
	declare cur1 cursor for 
			select sc.state_key, sc.state_code, dy.year_num
            from cms_source.state_codes sc, cms_source.data_years dy
			order by sc.state_code, dy.year_num;

    declare continue handler for not found set done = 1;   -- looks for the end of the result set
 
	-- this opens the cursor. (It runs the query)   
    open cur1;

read_loop:	loop
    
		-- this brings the first (next) row of data into the listed variables.
		fetch cur1 into  st_key, st_cd, year_num;
        
		if done then
			leave read_loop;
		end if;

-- this is where you insert columns into your new table from the source table
		insert into Re_taf_demog_elig_base
			(PATIENT_ID, BENE_ID, STATE_CD, STATE_KEY, RFRNC_YR, BIRTH_DT, 
             AGE, AGE_GRP_CD, DEATH_DT, SEX_CD, ETHNCTY_CD, RACE_ETHNCTY_CD)
			select
				patient_id, 
                BENE_ID,
				st_cd as STATE_CD,
                st_key as STATE_KEY,
				year_num as RFRNC_YR,
                BIRTH_DT,
                AGE,
                AGE_GRP_CD,
                DEATH_DT,
                SEX_CD, 
                ETHNCTY_CD,
                RACE_ETHNCTY_CD
			from cms_source.taf_demog_elig_base
			where STATE_KEY = st_key
			and RFRNC_YR = year_num;
  
	end loop;
	close cur1; 
	
end$$			
DELIMITER ;

CALL Re_taf_demog_loop();