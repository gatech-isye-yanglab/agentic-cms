# Examples — Known-Good Code Sets

These JSON files are the **validation targets** for the code-lookup system.
When the agent translates a natural-language disease description into a
structured code set, the output should closely match the file for that disease.

## Files

| File | Disease | Status | Source |
|---|---|---|---|
| `diabetes_codes.json` | Diabetes (T1 + T2, with complications) | Complete — 86 ICD-10, 65 ICD-9, 57 HCPCS codes | Hand-curated from gold-standard reference SQL: [`pipelines/diabetes/reference/`](../../pipelines/diabetes/reference/) |
| `lung_cancer_codes.json` | Lung cancer | Interim — derived from PhecodeX + CDC ICD-10-CM + CMS ICD-9-CM + AHRQ CCSR | PhecodeX `CA_102.1` / `CA_114.42` / `CA_137.1`; CDC ICD-10-CM C34.\*; CMS v32 ICD-9-CM 162.\*; AHRQ CCSR NEO022 |

## Schema

Each code-set JSON file carries:

- `disease` — one-line label
- `source_project` — where the codes originated
- `source_files` — exact files the codes were extracted from
- `inclusion_logic` — natural-language description of the clinical criterion (e.g., "≥2 claims within 24 months")
- `cohort_constraints` — non-code filters (states, dates, age)
- `icd10`, `icd9`, `hcpcs` — arrays of `{code, description}` entries. Descriptions come from the public reference data described in [`databases/README.md`](../databases/README.md).
- `notes` — caveats (e.g., category-level codes not in leaf files, historical typos preserved for fidelity)
- `generated_at`, `generator` — provenance

## How to regenerate

**Diabetes:** parse the `INSERT INTO ... VALUES (...)` SQL in
[`pipelines/diabetes/reference/icd_code.sql`](../../pipelines/diabetes/reference/icd_code.sql)
and [`pipelines/diabetes/reference/hcpcs_code.sql`](../../pipelines/diabetes/reference/hcpcs_code.sql),
then look up descriptions from the downloaded reference files.

**Lung cancer (interim):** search the local PhecodeX CSV (`databases/phewas/phecodeX_info.csv`)
for phecodes whose description contains "lung" or "bronchus", then join those
phecodes to `databases/phewas/phecodeX_unrolled_ICD_CM.csv` to get the ICD-9-CM
and ICD-10-CM member codes. Supplement with full-leaf sweeps of `C34*` from
the CDC ICD-10-CM 2026 release and `162*` from CMS v32 ICD-9-CM. Cross-reference
with AHRQ CCSR category NEO022 ("Respiratory cancers"). When a hand-curated
clinical list is available, diff against this interim set.
