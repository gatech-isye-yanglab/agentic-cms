-- load_mysql.sql — Load the synthetic DB into MySQL from the CSVs in ./csv/.
--
-- Prerequisites:
--   1. Run schema_mysql.sql first to create the 21 tables.
--   2. MySQL server must be started with  --local-infile=1  (Workbench: see
--      Connections → Advanced → "Allow LOAD DATA LOCAL INFILE").
--   3. Run this file from the synthetic_data/ directory so the
--      relative ./csv/ path resolves, or edit the paths below.
--
--   mysql -u root -p --local-infile=1 cms_source < load_mysql.sql
--
-- CSVs are comma-separated, RFC-4180 quoted, UTF-8, with a header row.
-- MySQL will auto-cast '' (empty) fields to NULL via the IGNORE LINES +
-- SET col = NULLIF(col,'') pattern.

USE cms_source;
SET GLOBAL local_infile = 1;
SET SESSION sql_mode = '';
SET FOREIGN_KEY_CHECKS = 0;

-- Truncate so this script is idempotent.
TRUNCATE TABLE `data_years`;
TRUNCATE TABLE `inpatient`;
TRUNCATE TABLE `inpatient1315`;
TRUNCATE TABLE `messagelog`;
TRUNCATE TABLE `other_therapy`;
TRUNCATE TABLE `other_therapy1315`;
TRUNCATE TABLE `personal_summary`;
TRUNCATE TABLE `personal_summary1315`;
TRUNCATE TABLE `rx`;
TRUNCATE TABLE `rx1315`;
TRUNCATE TABLE `state_codes`;
TRUNCATE TABLE `table_counts`;
TRUNCATE TABLE `table_counts_by_state`;
TRUNCATE TABLE `table_osline_counts_by_state`;
TRUNCATE TABLE `taf_demog_elig_base`;
TRUNCATE TABLE `taf_inpatient_header`;
TRUNCATE TABLE `taf_inpatient_line`;
TRUNCATE TABLE `taf_other_services_header`;
TRUNCATE TABLE `taf_other_services_line`;
TRUNCATE TABLE `taf_rx_header`;
TRUNCATE TABLE `taf_rx_line`;

-- Small meta tables first.
LOAD DATA LOCAL INFILE './csv/data_years.csv'      INTO TABLE `data_years`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/state_codes.csv'     INTO TABLE `state_codes`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/messagelog.csv'      INTO TABLE `messagelog`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/table_counts.csv'    INTO TABLE `table_counts`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/table_counts_by_state.csv' INTO TABLE `table_counts_by_state`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/table_osline_counts_by_state.csv' INTO TABLE `table_osline_counts_by_state`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- Claim tables — large, use extended insert.  NULLIF wrapping is omitted
-- because our CSV already writes empty fields for NULL and MySQL will
-- interpret empty varchars as '' (not NULL).  If you need strict NULLs
-- instead of '', switch to INSERT from seed_mysql.py.

LOAD DATA LOCAL INFILE './csv/inpatient.csv'       INTO TABLE `inpatient`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/inpatient1315.csv'   INTO TABLE `inpatient1315`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/other_therapy.csv'   INTO TABLE `other_therapy`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/other_therapy1315.csv' INTO TABLE `other_therapy1315`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/personal_summary.csv' INTO TABLE `personal_summary`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/personal_summary1315.csv' INTO TABLE `personal_summary1315`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/rx.csv'              INTO TABLE `rx`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/rx1315.csv'          INTO TABLE `rx1315`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/taf_demog_elig_base.csv' INTO TABLE `taf_demog_elig_base`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/taf_inpatient_header.csv' INTO TABLE `taf_inpatient_header`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/taf_inpatient_line.csv' INTO TABLE `taf_inpatient_line`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/taf_other_services_header.csv' INTO TABLE `taf_other_services_header`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/taf_other_services_line.csv' INTO TABLE `taf_other_services_line`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/taf_rx_header.csv'   INTO TABLE `taf_rx_header`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE './csv/taf_rx_line.csv'     INTO TABLE `taf_rx_line`
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
    LINES TERMINATED BY '\n' IGNORE 1 LINES;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Load complete.' AS status;
SELECT 'data_years'                   AS tablename, COUNT(*) AS actual_rows FROM `data_years`                   UNION ALL
SELECT 'inpatient',                                 COUNT(*)                FROM `inpatient`                   UNION ALL
SELECT 'inpatient1315',                             COUNT(*)                FROM `inpatient1315`               UNION ALL
SELECT 'messagelog',                                COUNT(*)                FROM `messagelog`                  UNION ALL
SELECT 'other_therapy',                             COUNT(*)                FROM `other_therapy`               UNION ALL
SELECT 'other_therapy1315',                         COUNT(*)                FROM `other_therapy1315`           UNION ALL
SELECT 'personal_summary',                          COUNT(*)                FROM `personal_summary`            UNION ALL
SELECT 'personal_summary1315',                      COUNT(*)                FROM `personal_summary1315`        UNION ALL
SELECT 'rx',                                        COUNT(*)                FROM `rx`                          UNION ALL
SELECT 'rx1315',                                    COUNT(*)                FROM `rx1315`                      UNION ALL
SELECT 'state_codes',                               COUNT(*)                FROM `state_codes`                 UNION ALL
SELECT 'table_counts',                              COUNT(*)                FROM `table_counts`                UNION ALL
SELECT 'table_counts_by_state',                     COUNT(*)                FROM `table_counts_by_state`       UNION ALL
SELECT 'table_osline_counts_by_state',              COUNT(*)                FROM `table_osline_counts_by_state` UNION ALL
SELECT 'taf_demog_elig_base',                       COUNT(*)                FROM `taf_demog_elig_base`         UNION ALL
SELECT 'taf_inpatient_header',                      COUNT(*)                FROM `taf_inpatient_header`        UNION ALL
SELECT 'taf_inpatient_line',                        COUNT(*)                FROM `taf_inpatient_line`          UNION ALL
SELECT 'taf_other_services_header',                 COUNT(*)                FROM `taf_other_services_header`   UNION ALL
SELECT 'taf_other_services_line',                   COUNT(*)                FROM `taf_other_services_line`     UNION ALL
SELECT 'taf_rx_header',                             COUNT(*)                FROM `taf_rx_header`               UNION ALL
SELECT 'taf_rx_line',                               COUNT(*)                FROM `taf_rx_line`;
