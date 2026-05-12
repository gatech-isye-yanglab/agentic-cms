# Reference Code Tables — Lung Cancer Pipeline

The lung-cancer pipeline joins against **four** reference tables:

| Table | Used by | Contents |
|---|---|---|
| `ICD910_lung_cancer_codes(icd910 varchar)` | `lung_inpatient_records_orig`, `lung_ospatient_records_orig` | ~40 ICD-9 + ICD-10 lung-cancer codes |
| `autoimmune_icd(icd910 varchar)` | `autoimmune_inpatient_records[_v2]`, `autoimmune_ospatient_records[_v2]`, `immuno_table_dm/hypo/ra` sub-slices | ~56 Super-PheWAS autoimmune categories × many ICD-9 + ICD-10 codes |
| `immuno_cpt_codes(cpt_code varchar)` | `immuno_ospatient_records`, `immuno_loop` | 6 HCPCS J-codes + 6 pre-approval C-codes for immune checkpoint inhibitors |
| `chemo_cpt_codes(cpt_code varchar)` | `chemo_ospatient_records`, `chemo_loop` | ~28 HCPCS codes for lung-cancer chemotherapy drugs |

The CSV/INSERT payloads for the four institutional tables were not exported
when the gold-standard pipeline was archived. The single SQL file in
this folder reconstructs them:

- [`build_reference_tables.sql`](build_reference_tables.sql) — populates
  all four tables from the public PhecodeX vocabulary plus the inline ICD
  list embedded in the gold-standard MAX-era pipeline. Run with
  `USE <scratch_db>;` first so the tables land where the step-1 procedures
  expect them.
- [`autoimmune_sub_slices.sql`](autoimmune_sub_slices.sql) — disease
  subgroup tables (`autoimmune_icd_dm`, `autoimmune_icd_hypo`,
  `autoimmune_icd_ra`, `autoimmune_icd_thyroiditis`, …) used by the
  per-disease procedures in [`../step5_consolidate/`](../step5_consolidate/).
  These are filtered subsets of `autoimmune_icd` by Super-PheWAS code.

## Provenance documentation

The four `*_legacy_claims.md` files in this folder are the **provenance
documentation** for the recovered code lists. They cite the published-
paper code lists the recovered benchmarks were derived from (a 2019 paper
on autoimmune adverse events in lung-cancer immunotherapy in commercial
claims data, which used the same PheWAS-anchored recipe). They are not
consumed at runtime.

- [`lung_cancer_icd_legacy_claims.md`](lung_cancer_icd_legacy_claims.md) — PheWAS 165.1 / PhecodeX `CA_102.1` anchor recipe + clinician-driven exclusions (209.21, 231.2).
- [`immuno_hcpcs_legacy_claims.md`](immuno_hcpcs_legacy_claims.md) — short list (C9453, J9299, C9027, J9271) plus the fuller 12-code list with pre-approval C-codes.
- [`autoimmune_icd_legacy_claims.md`](autoimmune_icd_legacy_claims.md) — Super-PheWAS rollup methodology for the autoimmune outcome anchors.
- [`chemo_hcpcs_legacy_claims.md`](chemo_hcpcs_legacy_claims.md) — chemotherapy J-code list + methotrexate-exclusion rationale.

The original reference paper used a commercial-claims schema
(`<provider>DataWarehouse.dbo.MedicalClaims` on SQL Server with
`DiagnosisCode1..6`); the ICD/HCPCS identifier sets transfer directly to
CMS Medicaid TAF/MAX even though the schemas differ.

## Why this matters for the agent

The central claim of the multi-agent project is that a general-purpose
health-informatics agent should be able to **generate these four tables
automatically** from a natural-language disease prompt by looking up ICD
and HCPCS codes in the public reference databases (PheWAS Catalog, CMS
ICD-9/ICD-10 lists, GEMs crosswalk, AHRQ CCSR, HCPCS quarterly). See
[`../../../cohort_identification/architecture_proposal.md`](../../../cohort_identification/architecture_proposal.md)
for the recipe.

In that frame, the four tables above are the **gold-standard validation
benchmark**, not an input the agent cribs from. A concrete test:

```
  NL prompt: "identify patients with lung cancer"
      ↓ agent consults PheWAS + ICD-9/ICD-10 CMS lists + GEMs
      ↓ agent outputs its proposed ICD set
      ↓ compare against ICD910_lung_cancer_codes
      ↓ precision / recall / F1 vs. the hand-curated list
```

The same exercise for `autoimmune_icd` is the harder test — the autoimmune
list is ~56 Super-PheWAS categories rolled up, so getting to the right set
from a prompt like "autoimmune adverse events of immunotherapy" requires
the agent to understand the PheWAS rollup structure, not just one-to-one
code lookup.
