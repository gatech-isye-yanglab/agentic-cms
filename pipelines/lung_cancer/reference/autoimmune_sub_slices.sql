-- =====================================================================
-- autoimmune_sub_slices.sql — per-disease sub-slices of `autoimmune_icd`
--
-- Referenced by step5_consolidate/final_tables.sql (procedures
-- immuno_table_dm, immuno_table_hypo, immuno_table_ra).
--
-- Because `autoimmune_icd` now carries `phecode_anchor` (see
-- build_reference_tables.sql), per-disease sub-slices are one-line VIEWS
-- filtered by anchor code rather than hand-curated separate tables. This
-- is the intended forward-looking shape: adding a new sub-slice means
-- one CREATE VIEW line plus the PhecodeX anchor(s), not re-curating an
-- ICD list.
--
-- Source: the published thesis Appendix C Tables S4-1…S4-6 (not yet imported
-- in full). The PhecodeX anchors below are the minimal seed from
-- build_reference_tables.sql; expand as the full thesis rollup arrives.
-- =====================================================================

DROP VIEW IF EXISTS autoimmune_icd_dm;
CREATE VIEW autoimmune_icd_dm AS
SELECT * FROM autoimmune_icd
WHERE phecode_anchor IN ('EM_202.1', 'EM_218.21');
  -- EM_202.1    Type 1 diabetes
  -- EM_218.21   Autoimmune polyglandular failure (endocrine)

DROP VIEW IF EXISTS autoimmune_icd_hypo;
CREATE VIEW autoimmune_icd_hypo AS
SELECT * FROM autoimmune_icd
WHERE phecode_anchor LIKE 'EM_200.1%';
  -- EM_200.1    Hypothyroidism
  -- EM_200.11   Secondary hypothyroidism
  -- EM_200.12   Hypothyroidism (not specified as secondary)

DROP VIEW IF EXISTS autoimmune_icd_thyroiditis;
CREATE VIEW autoimmune_icd_thyroiditis AS
SELECT * FROM autoimmune_icd
WHERE phecode_anchor LIKE 'EM_200.4%';
  -- EM_200.4    Thyroiditis
  -- EM_200.41   Chronic thyroiditis
  -- EM_200.411  Hashimoto
  -- EM_200.42   Acute thyroiditis
  -- EM_200.43   Subacute thyroiditis
  -- EM_200.45   Drug-induced / iatrogenic thyroiditis  (ICI-specific)

DROP VIEW IF EXISTS autoimmune_icd_thyro;
CREATE VIEW autoimmune_icd_thyro AS
SELECT * FROM autoimmune_icd_thyroiditis;
  -- Short alias — the gold standard procedure names (immuno_table_thyro,
  -- chemo_table_thyro) reference `autoimmune_icd_thyro` specifically.

DROP VIEW IF EXISTS autoimmune_icd_ra;
CREATE VIEW autoimmune_icd_ra AS
SELECT * FROM autoimmune_icd
WHERE phecode_anchor LIKE 'MS_705%';
  -- MS_705.1    Rheumatoid arthritis
  -- MS_705.11   RA without rheumatoid factor
  -- MS_705.12   RA with rheumatoid factor

-- Additional sub-slices referenced in the autoimmune_icd_legacy_claims.md
-- reconstruction but not yet used by step5_consolidate/final_tables.sql.
-- Wired up here so they're available when thesis Tables S4 arrive and
-- the gold-standard per-subgroup Cox models get reproduced.

DROP VIEW IF EXISTS autoimmune_icd_myalgia;
CREATE VIEW autoimmune_icd_myalgia AS
SELECT * FROM autoimmune_icd WHERE 1 = 0;  -- placeholder: polymyalgia rheumatica anchor not yet in seed

DROP VIEW IF EXISTS autoimmune_icd_colitis;
CREATE VIEW autoimmune_icd_colitis AS
SELECT * FROM autoimmune_icd
WHERE phecode_anchor = 'GI_522.12';  -- Ulcerative colitis (ICI colitis is the target)

DROP VIEW IF EXISTS autoimmune_icd_pneumonitis;
CREATE VIEW autoimmune_icd_pneumonitis AS
SELECT * FROM autoimmune_icd
WHERE phecode_anchor IN ('RE_477.2', 'RE_481.43');
  -- RE_477.2    Hypersensitivity pneumonitis
  -- RE_481.43   Interstitial pneumonitis
