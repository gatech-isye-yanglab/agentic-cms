# Cohort Identification Architecture — PheWAS Anchor Pattern

## 1. Why This Document Exists

Across the disease-specific cohort SQL we've reviewed (lung cancer, brain
cancer, melanoma, head-and-neck, diabetes), the same concrete recipe shows
up:

> Cohort identification is a 3-step recipe that is **identical across
> diseases**, plus an optional clinician-exclusion step that **is**
> disease-specific.

This document captures that recipe and proposes an architecture for the
agent's code-lookup tooling around it.

---

## 2. The Core Recipe

### Step 1: Anchor — Map disease name to PheWAS code(s)

```
"lung cancer"  →  PhecodeX CA_102.1   (legacy phecode v1.2: 165.1)
"brain cancer" →  PhecodeX CA_109.3   (legacy: 191.11)
"melanoma"     →  PhecodeX CA_103.1   (legacy: 172.11)
"head & neck"  →  PhecodeX CA_100.1, .2, .3, .4, .7  (legacy: 195.3 + 145.* + 149.*)
"diabetes"     →  PheWAS 250.x family + complications across multiple PhecodeX families
```

This is a clinical-taxonomy lookup. The PheWAS Catalog (PhecodeX v1.0) is the
reference database. Some diseases require **multiple** PheWAS anchors
(head & neck cancer; the autoimmune spectrum).

### Step 2: Pull — Get ICD-9 and ICD-10 children from the PheWAS crosswalk

```sql
-- Forward-looking form (PhecodeX v1.0, MySQL):
CREATE TABLE <Disease>DiagCode AS
SELECT m.ICD AS code, i.phecode_num AS PheWASCode, i.phecode_string AS PheWASString,
       m.ICD_string AS IcdString, m.vocabulary_id
FROM phewas.phecodeX_ICD_CM_map_flat m
JOIN phewas.phecodeX_info i ON i.phecode = m.phecode
WHERE m.phecode = '<ANCHOR_CODE>';
```

In our system, the agent does this lookup against the local PheWAS CSVs in
`databases/phewas/` (or against the `phewas` MySQL DB built by
`load_phewas_mysql.sh`). The logic is identical: phecode in, ICD-9 + ICD-10
codes out.

### Step 3: Exclude — Drop "Personal history" codes

```sql
DELETE FROM <Disease>DiagCode
WHERE IcdString LIKE '%Personal history%';
```

V-codes (ICD-9) and Z-codes (ICD-10) that record prior disease rather than
current disease must be excluded. This is universal across all diseases.

### Step 4 (optional): Clinician-driven exclusions

These are disease-specific judgment calls that are **not visible** to a naive
code lookup:

| Disease | Exclusion | Reason |
|---|---|---|
| Lung cancer | Drop ICD-9 `209.21` (carcinoid tumor) | Biologically distinct from NSCLC/SCLC |
| Lung cancer | Drop ICD-9 `231.2` / ICD-10 `D02.2x` (carcinoma in situ) | Out of scope for treatment study |
| Lung cancer chemo | Exclude methotrexate (J9250/J9260) despite valid chemo J-code | Conflates with autoimmune treatment in this population |
| Autoimmune | Drop `V12.x` / `Z86.x` (personal history of disease) | Marks prior diagnosis, not current event |

The agent should **flag** codes that commonly trigger clinician overrides
and present them for human review, rather than silently including or
excluding them.

---

## 3. Treatment Code Lookup (HCPCS / NDC)

For studies that also identify treatment (immunotherapy, chemotherapy, etc.),
the canonical recipe is:

### Drug-class → HCPCS pattern

1. **Enumerate drugs in the class.** Given "immune checkpoint inhibitor" →
   list PD-1 inhibitors (nivolumab, pembrolizumab), PD-L1 inhibitors
   (atezolizumab, durvalumab, avelumab), CTLA-4 inhibitors (ipilimumab).
   This is a clinical-taxonomy step (DrugBank, FDA labels, ATC system).

2. **Map each drug → HCPCS J-code** from the CMS HCPCS quarterly release
   (in `databases/hcpcs/`).

3. **Include pre-approval C-codes.** For drugs approved within the study
   window, the temporary CMS C-code must also be searched or early claims
   are missed (e.g. nivolumab has both J9299 permanent and C9453
   pre-approval).

4. **NDC-level fallback for pharmacy claims.** Oral agents (e.g., EGFR
   inhibitors erlotinib/osimertinib) appear in pharmacy claims by NDC
   description text match, not HCPCS — `NdcDescription LIKE '%nivolumab%'`
   style matching.

### Diabetes HCPCS pattern (different from oncology)

The diabetes gold standard uses a curated list of 58 HCPCS codes covering
insulin (J1815, J1817–J1819), glucose monitoring supplies (A4253, A4259,
A9274–A9288), therapeutic shoes (A5500–A5512), insulin pumps (E0784,
E0780–E0783), and diabetes self-management training (G0108, G0109). These
are **not** derived from a PheWAS-like systematic lookup — they are a
hand-curated clinical list. The agent should maintain such lists as
reference examples (see [`examples/diabetes_codes.json`](examples/diabetes_codes.json))
rather than try to auto-derive them.

---

## 4. Architecture

### What the agent needs

| Component | Purpose | Location |
|---|---|---|
| **PheWAS Catalog CSVs (PhecodeX v1.0)** | Step 1 (anchor) + Step 2 (pull ICD children) | `databases/phewas/` |
| **ICD-9/ICD-10 code lists** | Description lookup, validation | `databases/icd/` |
| **GEMs crosswalk** | ICD-9 ↔ ICD-10 mapping for edge cases | `databases/icd/gems-cm-2018/` |
| **HCPCS quarterly release** | Drug → J-code mapping | `databases/hcpcs/` |
| **NDC directory** | Drug → NDC fallback for pharmacy claims | `databases/drugs/` |
| **CCSR categories** | Alternative disease grouping / validation | `databases/ccsr/` |
| **Known-good examples** | Validation targets for diabetes, lung cancer | [`examples/`](examples/) |
| **PheWAS anchor reference** | Disease → PheWAS code(s) quick lookup | [`examples/phewas_anchor_reference.md`](examples/phewas_anchor_reference.md) |

The reference databases listed above are publicly redistributable but large
(~400 MB combined) and not committed to this repo. See
[`databases/README.md`](databases/README.md) for download URLs and the
expected layout.

### The lookup tool (one tool, not many)

The 3-step recipe is concrete and mechanical enough that a single primary
tool covers it end-to-end:

```python
def lookup_disease_codes(disease_name: str) -> dict:
    """
    Input:  "lung cancer"
    Output: {
        "phewas_anchor": "CA_102.1",
        "icd10_codes": [{"code": "C34.0", "desc": "..."}, ...],
        "icd9_codes":  [{"code": "162.0", "desc": "..."}, ...],
        "excluded_history_codes": [...],   # dropped V/Z codes
        "flagged_for_review": [            # clinician-judgment candidates
            {"code": "209.21", "desc": "Carcinoid...", "reason": "Biologically distinct"}
        ]
    }
    """
    # 1. Map disease name → PheWAS code(s)
    # 2. Pull ICD children from the PheWAS CSV
    # 3. Exclude "Personal history" descriptions
    # 4. Flag known clinician-exclusion candidates
```

Plus two smaller utilities:

- `lookup_drug_codes.py` — drug name/class → HCPCS J-code + C-code + NDC
- `crosswalk_codes.py` — ICD-9 → ICD-10 (or reverse) via the GEMs files

### The skill file

A skill file (in `knowledge/skills/`) should encode:

1. **The recipe** — the 3-step PheWAS anchor pattern, written as agent
   instructions.
2. **Known clinician exclusions** — a table of disease-specific overrides
   the agent should flag.
3. **Treatment-code strategy** — when and how to also look up HCPCS / NDC
   codes (depends on whether the study is diagnosis-only or
   diagnosis + treatment).
4. **Multi-anchor diseases** — how to handle diseases that map to multiple
   PheWAS codes (head & neck, autoimmune spectrum, diabetes complications).
5. **Validation instruction** — compare output against `examples/` and flag
   discrepancies.

---

## 5. Integration with the Multi-Agent DAG

The lookup tool fits cleanly into the planned 6-node DAG:

- The **Orchestrator** parses the user's natural-language disease + criteria
  and calls `lookup_disease_codes`.
- The structured code-set is passed to the **Schema Agent** and **SQL Writer**
  via the agent state.
- "Flagged for review" candidates are surfaced by the **Critic** as
  optional human-review prompts before execution.

This separates the "mechanical, always apply" clinical reasoning (excluding
"Personal history") from the "disease-specific, sometimes apply" reasoning
(carcinoid, methotrexate). The mechanical layer lives in the lookup tool;
the disease-specific layer lives in the skill file as flags, not hard rules.

---

## 6. Status

**In place:**

1. Reference databases enumerated (see [`databases/README.md`](databases/README.md)
   for download URLs; the actual payloads are excluded from this repo on
   size grounds).
2. PheWAS MySQL schema and loader — [`schema_phewas_mysql.sql`](schema_phewas_mysql.sql),
   [`load_phewas_mysql.sh`](load_phewas_mysql.sh).
3. Known-good code sets — [`examples/diabetes_codes.json`](examples/diabetes_codes.json),
   [`examples/lung_cancer_codes.json`](examples/lung_cancer_codes.json).
4. PheWAS anchor reference table — [`examples/phewas_anchor_reference.md`](examples/phewas_anchor_reference.md).

**Planned (under the AWS Agentic AI grant Aim referenced in the top-level
proposal):**

1. `tools/lookup_disease_codes.py` — implements the 3-step recipe against the local CSVs.
2. `tools/lookup_drug_codes.py` — drug → HCPCS / NDC.
3. Skill file under [`knowledge/skills/`](../knowledge/skills/) encoding the recipe + flags.
4. Tests against the known-good examples (diabetes, lung cancer) measuring precision / recall.
