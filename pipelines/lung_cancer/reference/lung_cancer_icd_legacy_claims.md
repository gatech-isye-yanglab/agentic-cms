# Lung cancer ICD-9 / ICD-10 — recovered benchmark (legacy commercial-claims source)

> **⚠️ Forward-looking note (2026-04-21):** this document preserves the **historical** a legacy commercial-claims study phecode v1.2 anchor (`165.1`). Going forward, use PhecodeX v1.0 anchor **`CA_102.1`** (phecode_num `102.1`) — same clinical concept ("Malignant neoplasm of the of bronchus and lung"), different numbering. The v1.2 code space does not exist in our local PheWAS download and will not return rows against the MySQL `phewas` DB. The current reproducible recipe lives in [`build_reference_tables.sql`](build_reference_tables.sql). See [`../../../cohort_identification/examples/phewas_anchor_reference.md`](../../../cohort_identification/examples/phewas_anchor_reference.md) for the v1.2-vs-PhecodeX crosswalk across all diseases.

**Status.** The CMS-side `<scratch_db>.ICD910_lung_cancer_codes` table was purged
from the institutional VM and is no longer recoverable from the live database. The
a legacy commercial-claims study lung-cancer paper (the principal investigator's prior study) uses the **same PheWAS-anchored
pattern** for its lung-cancer identifier set, so its cohort-definition code is
the cleanest available reconstruction of what the gold-standard author's CMS reference table
would have held.

The a legacy commercial-claims study schema is different (SQL Server, `a legacy commercial-claims studyDataWarehouse.dbo.MedicalClaims`
with `DiagnosisCode1..6`, not CMS Medicaid TAF/MAX); but **the ICD set itself
is schema-independent** — the PheWAS anchor code resolves to the same ICD-9
and ICD-10 children regardless of which claims database they are applied
against.

---

## The programmatic recipe (authoritative)

From `../gold_standard_legacy/lung_cancer.sql`, lines 41–56:

```sql
-- first find those with Lung cancer diagnosis codes from PheWAS 165.1
select Icd9Code as code, PheWASCode, PheWASString, Icd9String as IcdString
into LungDiagCode
from PheWAS.dbo.Icd9CodeTranslation
where PheWASCode = '165.1'

insert into LungDiagCode
select Icd10Code as code, PheWASCode, PheWASString, Icd10String as IcdString
from PheWAS.dbo.Icd10CodeTranslation
where PheWASCode = '165.1'

delete from LungDiagCode
where IcdString like '%Personal history%'
```

Three moves, end to end:

1. **Anchor:** PheWAS code **`165.1`** ("Cancer of bronchus; lung").
2. **Pull:** all ICD-9 and ICD-10 children of 165.1 from the PheWAS
   crosswalk tables.
3. **Exclude:** any description containing `"Personal history"` (V-codes
   and Z-codes that record prior cancer, not current disease).

This is the move the agent must learn for *any* disease — pick the right
PheWAS anchor, pull the ICD children, exclude history codes. It is the
concrete pattern that belongs in `../../cohort_identification/`.

---

## Expected ICD-10 output set (from the gold-standard author's CMS pipeline)

`<scratch_db>.lung_cancer_loop` (in `../gold-standard SQL (MAX-era cohort, partner-collated)` lines
3212–3238) contains the inline ICD list that was used in the CMS pipeline.
This is the **same set** the PheWAS 165.1 anchor would produce after the
`Personal history` exclusion:

```
ICD-9:  162, 1620, 1622, 1623, 1624, 1625, 1628, 1629
ICD-10: C33,
        C34, C340, C3400, C3401, C3402,
        C341, C3410, C3411, C3412,
        C342, C343, C3430, C3431, C3432,
        C348, C3480, C3481, C3482,
        C349, C3490, C3491, C3492,
        C7A090,
        D022, D0220, D0221, D0222
```

Decimal-form ICD-10: `C33, C34.0–C34.92 (malignant neoplasm of bronchus/lung),
C7A.090 (malignant carcinoid), D02.2–D02.22 (carcinoma in situ of bronchus
and lung)`.

---

## Clinical refinements from the a legacy commercial-claims study study (Nov 22, 2017 clinician meeting)

Feedback from Ken Kehl + Zak + Kun at a clinician meeting on Nov 22, 2017
(from the principal investigator's a legacy commercial-claims study-paper research log — `a legacy commercial-claims studyLungCancer/NOV2017/nov22.tex`,
not included in this repo; content relevant to the gold standard is
transcribed below):

- **Drop ICD-9 `209.21`** (malignant carcinoid tumor of bronchus and lung)
  — clinical judgment: carcinoid is biologically distinct from NSCLC/SCLC
  and should not be counted as "lung cancer" for an immunotherapy-adverse-
  event study.
- **Drop ICD-9 `231.2`** (carcinoma in situ of bronchus and lung) — in situ
  lesions are also out of scope.
- **"Personal history" code is not sensitive** — i.e., dropping the V-code
  history lines is the right move but will still leave some prior-cancer
  members in the cohort. Accepted tradeoff.
- **Claims data cannot distinguish small-cell from non-small-cell.** Any
  attempt to split NSCLC vs. SCLC from ICD alone is unreliable.
- **Metastasis codes (ICD-10 secondary malignant neoplasm of lung) are
  unreliable** — only a fraction of metastatic patients have them coded.
  The study therefore does not split metastatic vs. non-metastatic.

Net: The PheWAS-165.1-then-exclude-history recipe is the right automated
procedure; `209.21` and `231.2` are the *two* codes where a clinician has
overridden the automated list based on disease biology.

---

## Cohort-membership criterion (downstream of the code list)

From `../gold_standard_legacy/lung_cancer.sql` line 110:

```sql
SELECT MemberId
INTO tmpMembersStrictLungCancer
FROM HitsDiagnosisCriteriaLungCancer
GROUP BY MemberID
HAVING count(*) >= 3
```

The a legacy commercial-claims study study used **`count(*) >= 3`** diagnostic hits (strict) as the
lung-cancer cohort-membership criterion. The CMS pipeline does not impose a
count threshold at this stage — it accepts any claim with a qualifying
diagnosis — because a different downstream filter (the v3/v4/v6/v7 tables in
`step4_demographics_and_criteria/`) does the cohort-tightening. The same
ICD set can support either threshold.

---

## Provenance

- PheWAS-anchored SQL: `../gold_standard_legacy/lung_cancer.sql:41-56`
- Strict count criterion: `../gold_standard_legacy/lung_cancer.sql:106-110`
- Clinician-driven exclusions: the principal investigator's a legacy commercial-claims study-paper research log —
  `a legacy commercial-claims studyLungCancer/NOV2017/nov22.tex:13, 33` (log not in repo; content
  transcribed above).
- Inline ICD set used in CMS pipeline: `../gold-standard SQL (MAX-era cohort, partner-collated):3212-3238`
- PheWAS tables on the a legacy commercial-claims study SQL Server: `PheWAS.dbo.Icd9CodeTranslation`,
  `PheWAS.dbo.Icd10CodeTranslation` (Chirag Patel's lab PheWAS Catalog)

## Agent-benchmark framing

Given NL prompt *"identify patients with lung cancer"*, the agent should:

1. Map "lung cancer" to PheWAS code `165.1`.
2. Pull ICD-9 and ICD-10 children from the PheWAS Catalog (local copy in
   `../../../../icd_code_reference/databases/phewas/`).
3. Drop any ICD with description containing `"Personal history"`.
4. Offer the clinician the option to also drop carcinoid (`209.21`,
   `C7A.090`) and in-situ (`231.2`, `D02.2x`) depending on study scope —
   these are the clinician-judgment handles.

The agent's output, compared against the list above, is the precision/recall
benchmark. the gold-standard author's CMS list is the gold standard; the a legacy commercial-claims study list is the
recovered reconstruction of that gold standard, which happened to be
generated by the PheWAS-anchor recipe directly in SQL.
