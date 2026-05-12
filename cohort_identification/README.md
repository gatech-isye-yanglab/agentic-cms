# Cohort Identification — Public-Reference Code Lookup

The agent's "cohort identification" task is the step that translates
*"diabetes mellitus"* (a disease name in plain English) into the structured
list of ICD-9-CM, ICD-10-CM, HCPCS, and NDC codes a CMS Medicaid claims
query needs.

This folder holds the **reference data, schema, and known-good code sets**
that drive that translation, plus the architecture proposal for the
lookup tool itself.

## Contents

| Path | Purpose |
|---|---|
| [`architecture_proposal.md`](architecture_proposal.md) | The 3-step PheWAS-anchor recipe and the lookup-tool design. |
| [`schema_phewas_mysql.sql`](schema_phewas_mysql.sql) | MySQL DDL for the PhecodeX v1.0 reference DB (5 tables + 2 SQL-Server-dialect-compatibility views). |
| [`load_phewas_mysql.sh`](load_phewas_mysql.sh) | Loader that populates the schema from the PhecodeX CSVs. |
| [`databases/README.md`](databases/README.md) | Download URLs and expected layout for the public reference databases (~400 MB; not committed). |
| [`examples/diabetes_codes.json`](examples/diabetes_codes.json) | Validation target — 86 ICD-10, 65 ICD-9, 57 HCPCS codes for diabetes (T1+T2 with complications). |
| [`examples/lung_cancer_codes.json`](examples/lung_cancer_codes.json) | Validation target — interim lung-cancer code set derived from PhecodeX + CDC + CMS + AHRQ CCSR. |
| [`examples/phewas_anchor_reference.md`](examples/phewas_anchor_reference.md) | Quick-reference table mapping disease names to PheWAS anchor codes (PhecodeX v1.0 + legacy v1.2). |

## Quickstart

```bash
# 1. Download the public reference data (~400 MB) into databases/
#    See databases/README.md for the URLs and layout.

# 2. Build the phewas MySQL DB:
bash load_phewas_mysql.sh

# 3. Pull all ICD children of an anchor:
mysql -u root phewas -e "
  SELECT m.ICD AS code, m.ICD_string, m.vocabulary_id
  FROM phecodeX_ICD_CM_map_flat m
  WHERE m.phecode = 'CA_102.1'                          -- lung cancer
    AND m.ICD_string NOT LIKE '%Personal history%';
"
```

## Status

The lookup tool itself (`tools/lookup_disease_codes.py`,
`tools/lookup_drug_codes.py`) is part of the planned grant work and not
shipped here yet — see `architecture_proposal.md §6` for the planned scope.
What's in place today is the reference data layer and the validation
targets; an agent or human can already implement the 3-step recipe by hand
on top of the materials in this folder.
