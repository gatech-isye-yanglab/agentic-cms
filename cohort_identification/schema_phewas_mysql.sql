-- schema_phewas_mysql.sql — MySQL schema for the PheWAS reference tables.
--
-- Source of truth is the CSVs in `databases/phewas/` (PhecodeX v1.0).
-- This schema + `load_phewas_mysql.sh` build the joinable MySQL side.
-- Rebuild any time with:
--   bash load_phewas_mysql.sh
--
-- Collation note: utf8mb4_unicode_ci matches the synthetic `cms_source`
-- DB so cross-DB joins (claims.DIAG_CD_x = phewas.ICD) don't hit "Illegal
-- mix of collations".

DROP DATABASE IF EXISTS phewas;
CREATE DATABASE phewas
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;
USE phewas;

-- 1. PhecodeX definitions — 3,612 rows.
DROP TABLE IF EXISTS phecodeX_info;
CREATE TABLE phecodeX_info (
  phecode        VARCHAR(20)  NOT NULL,
  phecode_string VARCHAR(255),
  category_num   VARCHAR(8),
  category       VARCHAR(64),
  sex            VARCHAR(16),
  icd10_only     TINYINT,
  phecode_num    VARCHAR(20),
  PRIMARY KEY (phecode),
  KEY idx_phecode_num (phecode_num),
  KEY idx_category    (category_num)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Flat map: one row per (ICD, phecode) with ICD description — 79,597 rows.
DROP TABLE IF EXISTS phecodeX_ICD_CM_map_flat;
CREATE TABLE phecodeX_ICD_CM_map_flat (
  ICD            VARCHAR(16) NOT NULL,
  vocabulary_id  VARCHAR(16) NOT NULL,       -- ICD9CM | ICD10CM
  ICD_string     VARCHAR(512),
  phecode        VARCHAR(20) NOT NULL,
  phecode_string VARCHAR(255),
  category_num   VARCHAR(8),
  category       VARCHAR(64),
  KEY idx_icd          (ICD),
  KEY idx_phecode      (phecode),
  KEY idx_vocab_phecode(vocabulary_id, phecode)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Unrolled map: one row per (phecode, ICD) covering every descendant —
--    156,672 rows. THIS is the one cohort queries should join against.
DROP TABLE IF EXISTS phecodeX_unrolled_ICD_CM;
CREATE TABLE phecodeX_unrolled_ICD_CM (
  phecode       VARCHAR(20) NOT NULL,
  ICD           VARCHAR(16) NOT NULL,
  vocabulary_id VARCHAR(16) NOT NULL,
  KEY idx_phecode       (phecode),
  KEY idx_icd           (ICD),
  KEY idx_vocab_phecode (vocabulary_id, phecode)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. WHO flat map (not typically used for CMS, kept for completeness) — 11,403 rows.
DROP TABLE IF EXISTS phecodeX_ICD_WHO_map_flat;
CREATE TABLE phecodeX_ICD_WHO_map_flat (
  icd            VARCHAR(16) NOT NULL,
  vocabulary_id  VARCHAR(16) NOT NULL,
  ICD_string     VARCHAR(512),
  phecode        VARCHAR(20) NOT NULL,
  phecode_string VARCHAR(255),
  category_num   VARCHAR(8),
  category       VARCHAR(64),
  KEY idx_icd     (icd),
  KEY idx_phecode (phecode)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. WHO unrolled — 20,255 rows.
DROP TABLE IF EXISTS phecodeX_unrolled_ICD_WHO;
CREATE TABLE phecodeX_unrolled_ICD_WHO (
  phecode       VARCHAR(20) NOT NULL,
  ICD           VARCHAR(16) NOT NULL,
  vocabulary_id VARCHAR(16) NOT NULL,
  KEY idx_phecode (phecode),
  KEY idx_icd     (ICD)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------
-- Views: SQL-Server-dialect-compatibility shims.
--
-- A common legacy pan-cancer query shape targets
-- `PheWAS.dbo.Icd9CodeTranslation` and `PheWAS.dbo.Icd10CodeTranslation`
-- on SQL Server. These views let the same query shape work here with
-- `phewas.Icd9CodeTranslation` / `phewas.Icd10CodeTranslation`.
--
-- Column aliases match the original SQL-Server column names byte-for-byte so
-- the only change needed to port a legacy query is the schema prefix.
--
-- NOTE on code systems: PhecodeX v1.0 is a different numbering than the
-- older phecode v1.2. Legacy SQL using v1.2 codes like '165.1' for lung
-- cancer will NOT match — the equivalent in PhecodeX is 'CA_102.1'. The
-- views expose `PheWASCode = phecode_num`, so queries written against
-- PhecodeX naturals work; queries written against v1.2 anchors need a
-- mapping layer.

DROP VIEW IF EXISTS Icd9CodeTranslation;
CREATE VIEW Icd9CodeTranslation AS
SELECT
  m.ICD             AS Icd9Code,
  m.ICD_string      AS Icd9String,
  m.phecode_string  AS PheWASString,
  i.phecode_num     AS PheWASCode,
  m.phecode         AS phecode,
  m.category        AS category
FROM phecodeX_ICD_CM_map_flat m
JOIN phecodeX_info i ON i.phecode = m.phecode
WHERE m.vocabulary_id = 'ICD9CM';

DROP VIEW IF EXISTS Icd10CodeTranslation;
CREATE VIEW Icd10CodeTranslation AS
SELECT
  m.ICD             AS Icd10Code,
  m.ICD_string      AS Icd10String,
  m.phecode_string  AS PheWASString,
  i.phecode_num     AS PheWASCode,
  m.phecode         AS phecode,
  m.category        AS category
FROM phecodeX_ICD_CM_map_flat m
JOIN phecodeX_info i ON i.phecode = m.phecode
WHERE m.vocabulary_id = 'ICD10CM';
