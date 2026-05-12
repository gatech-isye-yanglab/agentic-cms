# Reference Databases — Public Sources

The cohort-identification tooling reads from a set of **public reference
databases**. They are publicly redistributable but large in aggregate
(~400 MB), so they are **not committed to this repository**. Download
them on demand into the layout below.

## Expected layout

```
cohort_identification/databases/
├── phewas/
│   ├── PhecodeXVocabulary-main/             # GitHub release of PhecodeX v1.0
│   ├── phecodeX_info.csv                    # 3,612 phecode definitions
│   ├── phecodeX_ICD_CM_map_flat.csv         # 79,597 (ICD ↔ phecode) rows w/ descriptions
│   ├── phecodeX_unrolled_ICD_CM.csv         # 156,672 (phecode → all descendant ICDs) rows
│   ├── phecodeX_ICD_WHO_map_flat.csv        # 11,403 — WHO variants
│   └── phecodeX_unrolled_ICD_WHO.csv        # 20,255
├── icd/
│   ├── icd10cm-2026/                        # CDC ICD-10-CM FY2026 (74,719 codes)
│   ├── icd9cm-v32/                          # CMS v32 ICD-9-CM (14,567 dx + 3,882 sg codes)
│   ├── gems-cm-2018/                        # ICD-9 ↔ ICD-10 diagnosis crosswalk (24,860 rows)
│   ├── gems-pcs-2018/                       # ICD-9 ↔ ICD-10 procedure crosswalk (81,593 rows)
│   ├── valid-icd-10-list.xlsx               # CMS valid-codes list
│   ├── excluded-icd-10-list.xlsx
│   ├── valid-icd-9-list.xlsx
│   └── excluded-icd-9-list.xlsx
├── hcpcs/
│   └── april-2026/HCPC2026_APR_ANWEB.txt    # CMS HCPCS Level II Apr 2026 (16,734 codes)
├── ccsr/
│   ├── DXCCSR-v2026-1/                      # AHRQ CCSR diagnosis (75,726 mappings)
│   └── PRCCSR-v2026-1/                      # AHRQ CCSR procedure (82,328 mappings)
└── drugs/
    ├── drug-ndc-0001-of-0001.json           # FDA NDC directory (134,205 NDCs)
    └── (RxNorm — optional; UTS account required, see below)
```

## Sources

| # | Database | Source URL | License |
|---|---|---|---|
| 1 | PhecodeX v1.0 | https://github.com/PheWAS/PhecodeXVocabulary | Public domain (NIH/NLM) |
| 2 | ICD-10-CM (CDC FY2026) | https://www.cdc.gov/nchs/icd/icd-10-cm/index.html | Public domain |
| 3 | ICD-9-CM diagnosis (CMS v32) | https://www.cms.gov/medicare/coding-billing/icd-10-codes/icd-9-cm-diagnosis-procedure-codes-abbreviated-and-full-code-titles | Public domain |
| 4 | GEMs ICD-9 ↔ ICD-10 (2018 final) | https://www.cms.gov/medicare/coding-billing/icd-10-codes/icd-10-cm-icd-10-pcs-gem-archive | Public domain |
| 5 | HCPCS Level II (CMS quarterly) | https://www.cms.gov/medicare/coding-billing/healthcare-common-procedure-system/quarterly-update | Public domain |
| 6 | AHRQ CCSR (v2026-1) | https://hcup-us.ahrq.gov/toolssoftware/ccsr/ccs_refined.jsp | Public domain |
| 7 | FDA NDC directory | https://api.fda.gov/download.json (`drug/ndc`) | openFDA, public |
| 8 | RxNorm (optional) | https://www.nlm.nih.gov/research/umls/rxnorm/ | Free with UTS account |

## Notes

- **RxNorm** requires a free NLM UTS account; direct fetch returns a 302 to
  the login page. The `RxNav` REST API is a lookup-by-name alternative that
  needs no login.
- **Phecode v1.2 definitions** (`phecode_definitions1.2.csv`) — the legacy
  pan-cancer code system. Not redistributed here; PhecodeX v1.0 supersedes it
  and is the recommended target for new work. If your code refers to v1.2
  anchors (e.g. `165.1` for lung cancer), see
  [`../examples/phewas_anchor_reference.md`](../examples/phewas_anchor_reference.md)
  for the PhecodeX equivalents (`CA_102.1` etc.).
- **Elixhauser / SNOMED / UMLS / LOINC / MS-DRG** are not part of the current
  cohort-lookup recipe. They can be added on a per-study basis.

## After download — load into MySQL

```bash
bash load_phewas_mysql.sh
```

builds the `phewas` MySQL DB from the PhecodeX CSVs (schema in
[`../schema_phewas_mysql.sql`](../schema_phewas_mysql.sql)).
