# PheWAS Anchor Reference — Known Disease-to-Code Mappings

**Source:** PhecodeX v1.0 vocabulary in `databases/phewas/`, plus a small set
of well-established anchor codes carried over from earlier pan-cancer
literature (phecode v1.2).

**Purpose:** Quick-reference table for the agent. When a disease appears here,
skip the PheWAS catalog search and use the known anchor directly.

**Forward-looking policy:** use **PhecodeX v1.0** for all new work. Phecode v1.2
columns are kept for traceability; the v1.2 code space is not present in the
local PhecodeX download (`phecode_definitions1.2.csv` is not redistributed
here), and the two code systems were renumbered non-trivially between
versions. Agent-generated queries should target the `phecode` / `phecode_num`
columns from PhecodeX v1.0.

---

## Disease → PheWAS Anchor Codes

| Disease | **PhecodeX v1.0 (use this)** | Phecode v1.2 (historical) | Multi-anchor? | Notes |
|---|---|---|---|---|
| Lung cancer | **`CA_102.1`** ("Malignant neoplasm of the bronchus and lung", 37 ICD children) | `165.1` | No | Optional clinician-exclude siblings: `CA_114.42` (carcinoid), `CA_137.1` (benign neoplasm) |
| Brain cancer | **`CA_109.3`** ("Malignant neoplasm of brain") | `191.11` | No | Broader parent `CA_109` covers eye + brain + CNS |
| Melanoma | **`CA_103.1`** ("Melanomas of skin") | `172.11` | No | |
| Head & neck cancer | **`CA_100.1, CA_100.2, CA_100.3, CA_100.4, CA_100.7`** (oral cavity / oropharynx / nasopharynx / hypopharynx / pharynx) | `195.3`, `145.*`, `149.*` | **Yes** | Parent `CA_100` is the umbrella "Malignant neoplasm of the head and neck" |
| Diabetes mellitus | see note below | `250.x` family | **Yes** | The diabetes pipeline currently uses a hand-curated ICD list in [`pipelines/diabetes/reference/icd_9_cm.sql`](../../pipelines/diabetes/reference/icd_9_cm.sql) rather than a single PheWAS rollup, because diabetes complications span multiple PhecodeX families |
| Autoimmune spectrum | ~56 categories — needs explicit PhecodeX-to-Super-PheWAS-category mapping | ~56 Super-PheWAS categories (T1D 250.1x, RA 714.x, …) | **Yes** | Multi-anchor pattern |

---

## The Universal SQL Recipe

### Forward-looking form (PhecodeX v1.0, MySQL — use this)

```sql
-- Pull all ICD-9-CM and ICD-10-CM children of the PhecodeX anchor.
-- Step 3 "Personal history" exclusion is applied via ICD_string in the flat map.
CREATE TABLE <Disease>DiagCode AS
SELECT m.ICD AS code, i.phecode_num AS PheWASCode, i.phecode_string AS PheWASString,
       m.ICD_string AS IcdString, m.vocabulary_id
FROM phewas.phecodeX_ICD_CM_map_flat m
JOIN phewas.phecodeX_info i ON i.phecode = m.phecode
WHERE m.phecode = '<ANCHOR_CODE>'            -- e.g. 'CA_102.1' for lung cancer
  AND m.ICD_string NOT LIKE '%Personal history%';
```

Or, if the query only needs the code strings (no descriptions):

```sql
SELECT ICD AS code, vocabulary_id
FROM phewas.phecodeX_unrolled_ICD_CM
WHERE phecode = 'CA_102.1';
```

See [`../schema_phewas_mysql.sql`](../schema_phewas_mysql.sql) for the MySQL
`phewas` DB schema and [`../load_phewas_mysql.sh`](../load_phewas_mysql.sh) for
how it's populated from the CSVs.

### Historical form (phecode v1.2, SQL Server — reference only)

The classic pan-cancer query shape uses the same 3-step pattern targeting
SQL-Server-dialect tables:

```sql
-- Step 1: Pull ICD-9 children of the PheWAS anchor
SELECT Icd9Code AS code, PheWASCode, PheWASString, Icd9String AS IcdString
INTO [Disease]DiagCode
FROM PheWAS.dbo.Icd9CodeTranslation
WHERE PheWASCode = '[V1.2_ANCHOR_CODE]'

-- Step 2: Add ICD-10 children
INSERT INTO [Disease]DiagCode
SELECT Icd10Code AS code, PheWASCode, PheWASString, Icd10String AS IcdString
FROM PheWAS.dbo.Icd10CodeTranslation
WHERE PheWASCode = '[V1.2_ANCHOR_CODE]'

-- Step 3: Exclude personal history codes
DELETE FROM [Disease]DiagCode
WHERE IcdString LIKE '%Personal history%'
```

Our MySQL `phewas` DB ships SQL-Server-dialect-compatibility views named
`Icd9CodeTranslation` / `Icd10CodeTranslation` so the only change needed to
port this form to MySQL is the schema prefix: `PheWAS.dbo.` → `phewas.`. Note
that the views expose `PheWASCode = phecode_num`, and `phecode_num` values
from PhecodeX don't match v1.2 anchors — prefer the forward-looking form
above for new code.

---

## Expected ICD Output Sets

### Lung cancer (PhecodeX `CA_102.1`)

ICD-9: `162, 1620, 1622, 1623, 1624, 1625, 1628, 1629`

ICD-10: `C33, C34, C340, C3400, C3401, C3402, C341, C3410, C3411, C3412,
C342, C343, C3430, C3431, C3432, C348, C3480, C3481, C3482, C349, C3490,
C3491, C3492, C7A090, D022, D0220, D0221, D0222`

Clinician exclusions (optional, depending on study scope):
- Drop `209.21` / `C7A.090` (carcinoid — biologically distinct)
- Drop `231.2` / `D02.2x` (carcinoma in situ — out of scope for treatment studies)

### Diabetes (hand-curated, broader than a single PheWAS anchor)

The diabetes gold standard includes 87 ICD-10/ICD-9 paired codes covering:
- Base diabetes: E10.x (Type 1), E11.x (Type 2) — PheWAS 250.x family
- Diabetic nephropathy: N18.x, 585.x
- Diabetic retinopathy: E11.3x, 362.0x — PheWAS 362.x family
- Diabetic neuropathy: G63.x, 357.2 — PheWAS 357.x family
- Cardiovascular complications: I25.x, 414.x

This is the **multi-anchor** pattern — the agent must look up not just the
base disease but also its known complication families.

Full code set: [`examples/diabetes_codes.json`](diabetes_codes.json) (86 ICD-10, 65 ICD-9, 57 HCPCS).

---

## Treatment Code Anchors (HCPCS)

### Immunotherapy (lung cancer)

| HCPCS | Drug | Target | Type |
|---|---|---|---|
| J9299 | Nivolumab | PD-1 | Permanent J-code |
| C9453 | Nivolumab | PD-1 | Pre-approval C-code |
| J9271 | Pembrolizumab | PD-1 | Permanent J-code |
| C9027 | Pembrolizumab | PD-1 | Pre-approval C-code |
| J9228 | Ipilimumab | CTLA-4 | Permanent J-code |
| J9022 | Atezolizumab | PD-L1 | Permanent J-code |
| J9173 | Durvalumab | PD-L1 | Permanent J-code |
| J9023 | Avelumab | PD-L1 | Permanent J-code |

Plus pre-approval C-codes: C9027, C9284, C9453, C9483, C9491, C9492.

### Chemotherapy (lung cancer)

| HCPCS | Drug | Class |
|---|---|---|
| J9060 | Cisplatin | Platinum |
| J9045 | Carboplatin | Platinum |
| J9267 | Paclitaxel | Taxane |
| J9264 | Nab-paclitaxel | Taxane (albumin-bound) |
| J9171 | Docetaxel | Taxane |
| J9201 | Gemcitabine | Antimetabolite |
| J9305 | Pemetrexed | Antifolate antimetabolite |
| J9390 | Vinorelbine | Vinca alkaloid |
| J9181 | Etoposide | Topoisomerase II inhibitor |
| J9206 | Irinotecan | Topoisomerase I inhibitor |
| J9035 | Bevacizumab | Anti-VEGF (targeted) |
| J9308 | Ramucirumab | Anti-VEGFR-2 (targeted) |

Clinician exclusion: **methotrexate (J9250 / J9260) excluded** despite being a
valid chemotherapy J-code — in lung-cancer study populations it conflates with
autoimmune treatment.

### Diabetes HCPCS (hand-curated, 58 codes)

Includes insulin (J1815, J1817–J1819), glucose monitoring (A4253, A4259,
A9274–A9288), therapeutic shoes (A5500–A5512), insulin pumps (E0784,
E0780–E0783), diabetes self-management training (G0108, G0109), and others.

Full list: [`pipelines/diabetes/reference/hcpcs_code.sql`](../../pipelines/diabetes/reference/hcpcs_code.sql).

---

## Multi-Anchor Diseases: Special Handling

### Head & neck cancer (3 PhecodeX families)

The head-and-neck SQL uses three separate `WHERE phecode = ...` blocks:
- `CA_100.1`–`CA_100.4`, `CA_100.7` — primary head/neck sites in PhecodeX
- Historical phecode v1.2: `195.3`, `145.*`, `149.*`

The agent must union results from all anchors, then apply the standard
"Personal history" exclusion to the combined set.

### Autoimmune spectrum (~56 categories)

The autoimmune table uses the full Super-PheWAS autoimmune category tree —
roughly 56 PheWAS anchors covering endocrine autoimmune (T1D, thyroiditis),
rheumatologic (RA, lupus), dermatologic (vitiligo), GI (colitis, hepatitis),
neurologic (myasthenia gravis), pulmonary (pneumonitis), renal (nephritis),
and hematologic (hemolytic anemia, thrombocytopenia).

Each ICD must be labeled with its Super-PheWAS category because downstream
analysis uses per-category models (e.g.,
`WHERE super_phewas_category = 'type1_dm'`).
