# Prompt 07 — Cohort identification: PhecodeX anchor recipe

## Goal

Generate `cohort_identification/` — the public-reference code-lookup
layer that translates disease names into ICD-9-CM / ICD-10-CM /
HCPCS / NDC code sets via the PhecodeX-anchor recipe.

The full-repo lookup *tools* (`tools/lookup_disease_codes.py`,
`tools/lookup_drug_codes.py`) are planned grant work and **not yet
implemented**. What ships today is the reference-data scaffolding
plus the architecture document that specifies the recipe.

## Files to generate (under `cohort_identification/`)

| File | Purpose |
|---|---|
| `README.md` | Top-level orientation: what this folder is, status. |
| `architecture_proposal.md` | The 3-step PheWAS-anchor recipe + lookup-tool design. |
| `schema_phewas_mysql.sql` | MySQL DDL for the PhecodeX v1.0 reference DB (5 tables + 2 SQL-Server-dialect-compatibility views). |
| `load_phewas_mysql.sh` | CSV loader that populates the schema from PhecodeX CSVs. |
| `databases/README.md` | Download URLs + expected layout for the public reference databases (~400 MB; not committed). |
| `examples/README.md` | Index for the validation-target JSONs. |
| `examples/diabetes_codes.json` | Validation target — copy from `seed/data/examples/diabetes_codes.json`. |
| `examples/lung_cancer_codes.json` | Validation target — copy from `seed/data/examples/lung_cancer_codes.json`. |
| `examples/phewas_anchor_reference.md` | Disease → PhecodeX/legacy-phecode anchor lookup table. |

## architecture_proposal.md — the recipe

The cohort-identification task is a **3-step recipe identical across
diseases**, plus an optional clinician-exclusion step that's disease-
specific:

### Step 1: Anchor — disease name → PheWAS code(s)

```
"lung cancer"  → PhecodeX CA_102.1   (legacy phecode v1.2: 165.1)
"brain cancer" → PhecodeX CA_109.3   (legacy: 191.11)
"melanoma"     → PhecodeX CA_103.1   (legacy: 172.11)
"head & neck"  → PhecodeX CA_100.{1,2,3,4,7}  (legacy: 195.3 + 145.* + 149.*)
"diabetes"     → PheWAS 250.x family + complications across multiple PhecodeX families
```

This is a clinical-taxonomy lookup. The PheWAS Catalog (PhecodeX v1.0)
is the reference DB. Some diseases require multiple anchors.

### Step 2: Pull — get ICD-9 + ICD-10 children from the PheWAS crosswalk

Forward-looking form (PhecodeX v1.0, MySQL):

```sql
CREATE TABLE <Disease>DiagCode AS
SELECT m.ICD AS code, i.phecode_num AS PheWASCode, i.phecode_string AS PheWASString,
       m.ICD_string AS IcdString, m.vocabulary_id
FROM phewas.phecodeX_ICD_CM_map_flat m
JOIN phewas.phecodeX_info i ON i.phecode = m.phecode
WHERE m.phecode = '<ANCHOR_CODE>'
  AND m.ICD_string NOT LIKE '%Personal history%';
```

### Step 3: Exclude — drop "Personal history" codes

`DELETE FROM <Disease>DiagCode WHERE IcdString LIKE '%Personal history%'`.
Universal across all diseases.

### Step 4 (optional): Clinician-driven exclusions

Disease-specific judgment calls. Examples:

- Lung cancer: drop ICD-9 `209.21` (carcinoid — biologically distinct)
- Lung cancer: drop ICD-9 `231.2` / ICD-10 `D02.2x` (carcinoma in situ)
- Lung cancer chemo: exclude methotrexate (J9250/J9260) despite
  valid chemo J-code (conflates with autoimmune treatment)
- Autoimmune: drop V12.x / Z86.x (personal history)

The agent should **flag** these for human review, not silently
include or exclude.

### Treatment-code recipe (HCPCS + NDC)

For diagnosis+treatment studies, a parallel recipe:

1. Enumerate drugs in the class (clinical taxonomy: DrugBank, FDA).
2. Map each drug → HCPCS J-code from the CMS HCPCS quarterly release.
3. Include pre-approval C-codes for drugs approved within the study
   window.
4. NDC fallback for pharmacy claims (oral agents not in HCPCS).

### Architecture recommendation

A single primary tool `lookup_disease_codes(disease_name) -> dict`
returning `{phewas_anchor, icd10_codes, icd9_codes,
excluded_history_codes, flagged_for_review}`. Plus two utilities:
`lookup_drug_codes`, `crosswalk_codes`. State that these tools are
**planned grant work, not shipped today.**

### Status section

Distinguish "in place" (reference DBs documented; PheWAS MySQL
schema + loader; validation-target JSONs; PhecodeX anchor reference)
from "planned" (the lookup tools themselves).

## schema_phewas_mysql.sql

5 tables + 2 views:

- `phecodeX_info` (phecode definitions; PRIMARY KEY phecode; INDEX
  phecode_num, category_num) — ~3,612 rows
- `phecodeX_ICD_CM_map_flat` (one row per ICD↔phecode with
  description; INDEX icd, phecode, vocabulary_id+phecode) — ~79,597 rows
- `phecodeX_unrolled_ICD_CM` (one row per phecode→descendant ICD;
  similar indexes) — ~156,672 rows; this is the table cohort
  queries should JOIN against
- `phecodeX_ICD_WHO_map_flat`, `phecodeX_unrolled_ICD_WHO` — WHO
  variants for completeness

2 SQL-Server-dialect-compatibility views:

- `Icd9CodeTranslation`: SELECTs from `phecodeX_ICD_CM_map_flat`
  WHERE `vocabulary_id = 'ICD9CM'`, exposing column aliases
  `Icd9Code`, `Icd9String`, `PheWASString`, `PheWASCode` (= phecode_num),
  `phecode`, `category` — letting legacy SQL-Server-dialect queries
  port to MySQL by changing only the schema prefix.
- `Icd10CodeTranslation`: same shape for `ICD10CM`.

Use `utf8mb4_unicode_ci` collation throughout (matches `cms_source`
so cross-DB joins don't hit "Illegal mix of collations").

## load_phewas_mysql.sh

`bash` script that runs `schema_phewas_mysql.sql` then issues `LOAD
DATA LOCAL INFILE` for each of the 5 CSVs in `databases/phewas/`. End
with a smoke test SELECT confirming the row counts.

## databases/README.md

Public-source URLs and expected layout for ~400 MB of reference data
that is **not committed** (gitignored):

| # | DB | URL | License |
|---|---|---|---|
| 1 | PhecodeX v1.0 | https://github.com/PheWAS/PhecodeXVocabulary | Public domain |
| 2 | ICD-10-CM (CDC FY2026) | https://www.cdc.gov/nchs/icd/icd-10-cm/index.html | Public domain |
| 3 | ICD-9-CM diagnosis (CMS v32) | https://www.cms.gov/medicare/coding-billing/icd-10-codes/icd-9-cm-diagnosis-procedure-codes-abbreviated-and-full-code-titles | Public domain |
| 4 | GEMs ICD-9 ↔ ICD-10 (2018) | https://www.cms.gov/medicare/coding-billing/icd-10-codes/icd-10-cm-icd-10-pcs-gem-archive | Public domain |
| 5 | HCPCS Level II (CMS quarterly) | https://www.cms.gov/medicare/coding-billing/healthcare-common-procedure-system/quarterly-update | Public domain |
| 6 | AHRQ CCSR v2026-1 | https://hcup-us.ahrq.gov/toolssoftware/ccsr/ccs_refined.jsp | Public domain |
| 7 | FDA NDC | openFDA `drug/ndc` | openFDA, public |
| 8 | RxNorm (optional) | https://www.nlm.nih.gov/research/umls/rxnorm/ | Free with UTS account |

Plus expected directory tree under `databases/`.

## examples/

Two JSON validation targets and two markdown index/reference files.

`diabetes_codes.json` (carry over from `seed/data/examples/`):

- `disease`, `source_project`, `source_files`, `inclusion_logic`,
  `cohort_constraints`, `icd10` (~86 entries), `icd9` (~65 entries),
  `hcpcs` (~57 entries), `notes`, `generated_at`, `generator`.

`lung_cancer_codes.json` (also carry over):

- Interim PhecodeX-derived list, with metadata describing it as
  "INTERIM — derived from public reference databases. A clinically-
  validated authoritative list will supersede this when available."
  Includes PhecodeX `CA_102.1` primary + `CA_114.42` carcinoid +
  `CA_137.1` benign sub-sections.

`phewas_anchor_reference.md`: a quick-reference table mapping disease
names → PhecodeX/legacy-phecode anchors, the universal SQL recipe
(forward-looking + historical), expected ICD output sets for lung
cancer + diabetes, treatment-code anchors (immunotherapy + chemo +
diabetes HCPCS), and multi-anchor disease handling (head & neck,
autoimmune spectrum).

`examples/README.md`: short index pointing at the two JSONs and
explaining their schema + how to regenerate.

## See also

- Full-repo equivalents at `cohort_identification/{README.md, architecture_proposal.md, schema_phewas_mysql.sql, load_phewas_mysql.sh, databases/README.md, examples/}`.
- `seed/data/examples/{diabetes_codes,lung_cancer_codes}.json` — validation targets to carry over verbatim.
- Prompt 06 for the lung-cancer pipeline that consumes this folder.
