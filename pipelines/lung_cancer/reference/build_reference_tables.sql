-- =====================================================================
-- build_reference_tables.sql — forward-looking replacement for the four
-- purged `<scratch_db>.*` reference tables.
--
-- Populates the four code-list tables that step1_extraction/*.sql joins
-- against. They live in the current database (run with
-- `USE <scratch_db>;`) so the step1 SQL — which no longer carries the
-- `<scratch_db>.` schema prefix — can find them unqualified.
--
-- Anchor mapping (v1.2 → PhecodeX v1.0):
--   lung cancer              165.1     → CA_102.1
--   brain cancer             191.11    → CA_109.3
--   melanoma                 172.11    → CA_103.1
--   head & neck cancer       195.3+... → CA_100.1..CA_100.7 (5 anchors)
--
-- See `../../../cohort_identification/examples/phewas_anchor_reference.md`
-- for the crosswalk and `../../../cohort_identification/schema_phewas_mysql.sql`
-- for the PheWAS MySQL schema.
--
-- Collation note: all four tables are explicitly utf8mb4_unicode_ci so that
-- joins against cms_source.taf_*.DGNS_CD_n / .LINE_PRCDR_CD (same collation)
-- don't hit "Illegal mix of collations".
-- =====================================================================

-- ---- 1. ICD910_lung_cancer_codes — derived from PhecodeX CA_102.1 ----
--
-- The 3-step PheWAS recipe, in one query:
--   step 1: pull ICD-9-CM and ICD-10-CM children of CA_102.1
--   step 2: apply "Personal history" exclusion via ICD_string
--   step 3: strip decimal points so the codes match CMS's DGNS_CD_n format
--           (CMS-loaded institutional tables store e.g. 'C3401', not 'C34.01')
--
-- Clinician-driven exclusions are applied separately (carcinoid CA_114.42,
-- benign neoplasm CA_137.1) — not bundled into CA_102.1, so nothing to
-- subtract here. If a future study wants them in/out, flip one join.

DROP TABLE IF EXISTS ICD910_lung_cancer_codes;
CREATE TABLE ICD910_lung_cancer_codes (
    icd910 VARCHAR(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO ICD910_lung_cancer_codes (icd910)
SELECT DISTINCT REPLACE(m.ICD, '.', '')
FROM phewas.phecodeX_ICD_CM_map_flat m
WHERE m.phecode = 'CA_102.1'
  AND m.ICD_string NOT LIKE '%Personal history%';

-- ---- 2. chemo_cpt_codes — HCPCS list, hand-curated ------------------
--
-- Source: `chemo_hcpcs_legacy_claims.md` (the published thesis Table C.1 + a legacy commercial-claims study log).
-- Methotrexate (J9250 / J9260) is INTENTIONALLY OMITTED — clinician
-- exclusion from the a legacy commercial-claims study Nov 22 2017 review. Including it would
-- conflate chemotherapy exposure with pre-existing autoimmune treatment
-- in this study population.

DROP TABLE IF EXISTS chemo_cpt_codes;
CREATE TABLE chemo_cpt_codes (
    cpt_code VARCHAR(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO chemo_cpt_codes (cpt_code) VALUES
    ('J9060'),  -- Cisplatin          (platinum, NSCLC first-line backbone)
    ('J9045'),  -- Carboplatin        (platinum)
    ('J9267'),  -- Paclitaxel         (taxane)
    ('J9264'),  -- Nab-paclitaxel     (taxane / Abraxane)
    ('J9171'),  -- Docetaxel          (taxane, NSCLC second-line)
    ('J9201'),  -- Gemcitabine        (antimetabolite)
    ('J9305'),  -- Pemetrexed         (antifolate, non-squamous NSCLC)
    ('J9390'),  -- Vinorelbine        (vinca alkaloid)
    ('J9181'),  -- Etoposide          (topoisomerase II)
    ('J9206'),  -- Irinotecan         (topoisomerase I)
    ('J9035'),  -- Bevacizumab        (anti-VEGF, targeted)
    ('J9308');  -- Ramucirumab        (anti-VEGFR-2, targeted)

-- ---- 3. immuno_cpt_codes — HCPCS list, hand-curated -----------------
--
-- Source: `immuno_hcpcs_legacy_claims.md` (thesis Table 4.2).
-- Six permanent J-codes + six pre-approval C-codes. Pre-approval codes
-- are essential — they catch 2014–2015 early-adopter claims before drugs
-- received their permanent J-code.

DROP TABLE IF EXISTS immuno_cpt_codes;
CREATE TABLE immuno_cpt_codes (
    cpt_code VARCHAR(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO immuno_cpt_codes (cpt_code) VALUES
    -- Permanent J-codes
    ('J9228'),  -- Ipilimumab   / Yervoy     (CTLA-4)
    ('J9299'),  -- Nivolumab    / Opdivo     (PD-1)
    ('J9271'),  -- Pembrolizumab / Keytruda  (PD-1)
    ('J9022'),  -- Atezolizumab / Tecentriq  (PD-L1)
    ('J9173'),  -- Durvalumab   / Imfinzi    (PD-L1)
    ('J9023'),  -- Avelumab     / Bavencio   (PD-L1)
    -- Pre-approval C-codes (must be included for early claims)
    ('C9027'),  -- Pembrolizumab pre-approval
    ('C9284'),  -- Ipilimumab pre-approval
    ('C9453'),  -- Nivolumab pre-approval
    ('C9483'),  -- Atezolizumab / emerging
    ('C9491'),  -- Durvalumab emerging
    ('C9492'); -- Avelumab emerging

-- ---- 4. autoimmune_icd — MINIMAL PhecodeX-derived seed set ----------
--
-- ⚠️ STUB. the published thesis Appendix C defines ~56 Super-PheWAS autoimmune
-- categories; that full enumeration is NOT yet imported. This seed covers
-- the most commonly-cited immune-related adverse events of checkpoint
-- inhibitor therapy (hypothyroidism, thyroiditis, T1D, autoimmune
-- hemolytic anemia, autoimmune-disease NOS, rheumatoid arthritis,
-- vitiligo, ulcerative colitis, autoimmune hepatitis, pancreatitis,
-- myasthenia gravis, pneumonitis) so the step1 extraction can run
-- end-to-end. It is NOT suitable for publishing a Cox HR — the gold-standard full set
-- has to replace it before Step 2–5 analysis is trustworthy.
--
-- Column `phecode_anchor` records which PhecodeX code each ICD came from,
-- so the downstream per-disease sub-slices (autoimmune_icd_dm,
-- autoimmune_icd_hypo, autoimmune_icd_ra) become one-line WHERE filters
-- rather than hand-curated separate tables.

DROP TABLE IF EXISTS autoimmune_icd;
CREATE TABLE autoimmune_icd (
    icd910         VARCHAR(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
    phecode_anchor VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
    category       VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
    KEY idx_icd (icd910),
    KEY idx_anchor (phecode_anchor)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO autoimmune_icd (icd910, phecode_anchor, category)
SELECT DISTINCT REPLACE(m.ICD, '.', ''), i.phecode, i.category
FROM phewas.phecodeX_ICD_CM_map_flat m
JOIN phewas.phecodeX_info i ON i.phecode = m.phecode
WHERE m.phecode IN (
    'EM_200.1',    -- Hypothyroidism          (→ hypo subgroup)
    'EM_200.11',
    'EM_200.12',
    'EM_200.4',    -- Thyroiditis             (→ thyroiditis subgroup)
    'EM_200.41',
    'EM_200.411',  -- Hashimoto
    'EM_200.42',
    'EM_200.43',
    'EM_200.45',   -- Drug-induced thyroiditis
    'EM_202.1',    -- Type 1 diabetes         (→ dm subgroup)
    'EM_218.21',   -- Autoimmune polyglandular failure
    'BI_161.21',   -- Autoimmune hemolytic anemia
    'BI_181',      -- Autoimmune disease, NOS
    'MS_705.1',    -- Rheumatoid arthritis    (→ ra subgroup)
    'MS_705.11',
    'MS_705.12',
    'DE_674.11',   -- Vitiligo
    'GI_522.12',   -- Ulcerative colitis      (ICI colitis)
    'GI_540.11',   -- Autoimmune hepatitis
    'GI_554.11',   -- Acute pancreatitis
    'NS_338.1',    -- Myasthenia gravis
    'RE_477.2',    -- Hypersensitivity pneumonitis
    'RE_481.43'    -- Interstitial pneumonitis
)
AND m.ICD_string NOT LIKE '%Personal history%';

-- Row-count sanity summary.
SELECT 'ICD910_lung_cancer_codes' AS reference_table, COUNT(*) AS rows_loaded FROM ICD910_lung_cancer_codes UNION ALL
SELECT 'chemo_cpt_codes',                              COUNT(*) FROM chemo_cpt_codes  UNION ALL
SELECT 'immuno_cpt_codes',                             COUNT(*) FROM immuno_cpt_codes UNION ALL
SELECT 'autoimmune_icd',                               COUNT(*) FROM autoimmune_icd;
