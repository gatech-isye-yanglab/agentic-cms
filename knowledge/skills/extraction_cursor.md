# Skill: Extraction Cursor Pattern

## Purpose
Every extraction query against a CMS source table MUST use a partitioned cursor
loop — the institutional production server kills any unpartitioned full-table scan.

## Required Pattern (CROSS JOIN cursor — preferred)

Use a SINGLE cursor over a cross join of state_codes and data_years.
This avoids MySQL's nested-cursor DONE-flag bug (inner cursor exhaustion
can accidentally set done=1 and exit the outer loop).

```sql
DELIMITER $$
CREATE PROCEDURE {proc_name}()
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_state_key INT;
    DECLARE v_year_num INT;

    DECLARE cur1 CURSOR FOR
        SELECT sc.state_key, dy.year_num
        FROM cms_source.state_codes sc, cms_source.data_years dy
        WHERE dy.year_num BETWEEN {year_start} AND {year_end}
        ORDER BY sc.state_key, dy.year_num;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    OPEN cur1;
    read_loop: LOOP
        FETCH cur1 INTO v_state_key, v_year_num;
        IF done THEN
            LEAVE read_loop;
        END IF;

        INSERT INTO {output_table}
        SELECT *
        FROM cms_source.{source_table} inp
        WHERE inp.state_key = v_state_key
          AND inp.{year_col} = v_year_num
          AND ({disease_filter});

    END LOOP;
    CLOSE cur1;
END$$
DELIMITER ;

CALL {proc_name}();
```

## Placeholders
- `{proc_name}` — stored procedure name (from disease profile)
- `{output_table}` — target table name (from disease profile)
- `{source_table}` — CMS source table (inpatient / other_therapy / taf_inpatient_header / ...)
- `{year_col}` — YR_NUM for ERA1/ERA2; RFRNC_YR for TAF ERA3
- `{year_start}` / `{year_end}` — era year range (2005/2012, 2013/2015, 2016/2018)
- `{disease_filter}` — disease-specific ICD filter (from disease profile)

## ERA-specific column names
| ERA | Source tables | Diag cols | Year col | State col | Patient ID |
|-----|--------------|-----------|----------|-----------|------------|
| ERA1 2005-2012 | inpatient, other_therapy | DIAG_CD_1..9 / ..2 | YR_NUM | state_key | patient_id |
| ERA2 2013-2015 | inpatient1315, other_therapy1315 | DIAG_CD_1..9 / ..2 | YR_NUM | state_key | patient_id |
| ERA3 2016-2018 | taf_inpatient_header, taf_other_services_header | DGNS_CD_1..12 / ..2 | RFRNC_YR | STATE_KEY | PATIENT_ID |

## Nested cursor warning
If you use nested cursors instead of a cross join, you MUST declare a SEPARATE
done flag for each cursor (done_state, done_year) because MySQL's single
CONTINUE HANDLER FOR NOT FOUND sets a shared flag.
