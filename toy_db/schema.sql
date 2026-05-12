-- toy_db/schema.sql — minimal cms_source schema for the agent demo tests.
--
-- A 6-source-table + 2-meta-table subset of the institutional CMS Medicaid
-- schema, identifier-exact for the columns the diabetes pipeline reads.
-- Used by toy_db/seed_mysql.py to materialise a ~1,400-row fixture for
-- the agent prototype's smoke tests in tests/.
--
-- This is NOT the schema-exact synthetic CMS sandbox in
-- ../synthetic_data/ — that's the 21-table / 2,533-column public
-- contribution. This schema is just enough to drive the demo.

CREATE DATABASE IF NOT EXISTS cms_source
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;
USE cms_source;

DROP TABLE IF EXISTS inpatient;
CREATE TABLE inpatient (
  patient_id        VARCHAR(40),
  BENE_ID           VARCHAR(15),
  STATE_CD          VARCHAR(2),
  state_key         INT,
  YR_NUM            INT,
  EL_DOB            DATE,
  EL_SEX_CD         VARCHAR(1),
  EL_RACE_ETHNCY_CD VARCHAR(1),
  srvc_bgn_dt       DATE,
  srvc_end_dt       DATE,
  DIAG_CD_1 VARCHAR(8), DIAG_CD_2 VARCHAR(8), DIAG_CD_3 VARCHAR(8),
  DIAG_CD_4 VARCHAR(8), DIAG_CD_5 VARCHAR(8), DIAG_CD_6 VARCHAR(8),
  DIAG_CD_7 VARCHAR(8), DIAG_CD_8 VARCHAR(8), DIAG_CD_9 VARCHAR(8),
  KEY idx_partition (state_key, YR_NUM)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS inpatient1315;
CREATE TABLE inpatient1315 LIKE inpatient;

DROP TABLE IF EXISTS other_therapy;
CREATE TABLE other_therapy (
  patient_id        VARCHAR(40),
  BENE_ID           VARCHAR(15),
  STATE_CD          VARCHAR(2),
  state_key         INT,
  YR_NUM            INT,
  EL_DOB            DATE,
  EL_SEX_CD         VARCHAR(1),
  EL_RACE_ETHNCY_CD VARCHAR(1),
  srvc_bgn_dt       DATE,
  srvc_end_dt       DATE,
  DIAG_CD_1 VARCHAR(8), DIAG_CD_2 VARCHAR(8),
  KEY idx_partition (state_key, YR_NUM)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS other_therapy1315;
CREATE TABLE other_therapy1315 LIKE other_therapy;

DROP TABLE IF EXISTS taf_inpatient_header;
CREATE TABLE taf_inpatient_header (
  PATIENT_ID  VARCHAR(40),
  BENE_ID     VARCHAR(15),
  STATE_CD    VARCHAR(2),
  STATE_KEY   INT,
  RFRNC_YR    INT,
  BIRTH_DT    DATE,
  srvc_bgn_dt DATE,
  srvc_end_dt DATE,
  DGNS_CD_1  VARCHAR(7), DGNS_CD_2  VARCHAR(7), DGNS_CD_3  VARCHAR(7),
  DGNS_CD_4  VARCHAR(7), DGNS_CD_5  VARCHAR(7), DGNS_CD_6  VARCHAR(7),
  DGNS_CD_7  VARCHAR(7), DGNS_CD_8  VARCHAR(7), DGNS_CD_9  VARCHAR(7),
  DGNS_CD_10 VARCHAR(7), DGNS_CD_11 VARCHAR(7), DGNS_CD_12 VARCHAR(7),
  KEY idx_partition (STATE_KEY, RFRNC_YR)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS taf_other_services_header;
CREATE TABLE taf_other_services_header (
  PATIENT_ID  VARCHAR(40),
  BENE_ID     VARCHAR(15),
  STATE_CD    VARCHAR(2),
  STATE_KEY   INT,
  RFRNC_YR    INT,
  BIRTH_DT    DATE,
  srvc_bgn_dt DATE,
  srvc_end_dt DATE,
  DGNS_CD_1   VARCHAR(7),
  DGNS_CD_2   VARCHAR(7),
  KEY idx_partition (STATE_KEY, RFRNC_YR)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS state_codes;
CREATE TABLE state_codes (
  state_code VARCHAR(2),
  state_key  INT,
  PRIMARY KEY (state_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS data_years;
CREATE TABLE data_years (
  year_num INT PRIMARY KEY
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
