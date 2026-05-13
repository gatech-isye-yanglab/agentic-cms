# Chemotherapy HCPCS codes — recovered benchmark (legacy commercial-claims source)

**Status.** The CMS-side `<scratch_db>.chemo_cpt_codes` table was purged from
the institutional VM. The prior commercial-claims study lung-cancer research log names the chemotherapy
**drugs** used but does not enumerate HCPCS codes inline — the prior commercial-claims study
built its chemo table from `PharmacyCriteriaLungCancer` (pharmacy claims
matched by NDC description) rather than from a curated HCPCS list. So the
prior commercial-claims study source gives us the drug list; the HCPCS-code mapping for each drug
has to be re-derived from the CMS HCPCS quarterly release.

the published thesis Table C.1 is the gold-standard benchmark — ~28 HCPCS codes
covering the standard lung-cancer cytotoxic plus targeted-therapy set.

---

## The cytotoxic drug list (prior commercial-claims study-confirmed)

Standard lung-cancer cytotoxic chemotherapy drugs named in the prior-study research log
and the CMS pipeline:

| Drug | Class | Typical HCPCS J-code | Notes |
|---|---|---|---|
| Cisplatin | platinum | J9060 | first-line NSCLC backbone |
| Carboplatin | platinum | J9045 | NSCLC backbone alternative |
| Paclitaxel | taxane | J9267 | NSCLC first-line combo |
| Nab-paclitaxel | taxane (albumin-bound) | J9264 | Abraxane |
| Docetaxel | taxane | J9171 | NSCLC second-line |
| Gemcitabine | antimetabolite | J9201 | NSCLC first-line |
| Pemetrexed | antifolate antimetabolite | J9305 | non-squamous NSCLC |
| Vinorelbine | vinca alkaloid | J9390 | NSCLC |
| Etoposide | topoisomerase II inhibitor | J9181 | SCLC backbone |
| Irinotecan | topoisomerase I inhibitor | J9206 | SCLC |

HCPCS codes in the J-code column above are cross-referenced from the CMS
HCPCS quarterly release (see `../../../../icd_code_reference/databases/hcpcs/`
once that folder is populated). The codes here are representative — the
quarterly release is the authoritative source and should be the agent's
input.

---

## The targeted-therapy drug list (prior commercial-claims study-named)

Lung-cancer targeted agents named in the research log (from `JUN2017/jun2.tex`
and meeting notes):

| Drug | Target | HCPCS J-code |
|---|---|---|
| Bevacizumab / Avastin | VEGF | J9035 |
| Ramucirumab / Cyramza | VEGFR-2 | J9308 |

These are the anti-angiogenic agents; EGFR inhibitors (erlotinib, gefitinib,
afatinib, osimertinib) and ALK inhibitors (crizotinib, alectinib, etc.) are
typically dispensed as **oral** agents and appear in pharmacy claims rather
than HCPCS claims — they are retrieved by NDC description text match in the
prior commercial-claims study pipeline, not by HCPCS code lookup.

---

## Clinical refinement: methotrexate is **excluded**

From the principal investigator's prior-study research log
`prior-study log NOV2017/nov22.tex:15` (log not in repo; the one line of
content is:):

> chemotherapy definition -- delete chemo 8 methotrexate

Methotrexate is a chemotherapy agent for some diseases but is primarily an
immunosuppressive / antirheumatic drug in the lung-cancer study population.
Including it would conflate chemotherapy exposure with treatment for a
pre-existing autoimmune condition and corrupt the adverse-event analysis.

This is the clinician-driven exclusion the agent has to learn to honor —
it is not visible to a naive HCPCS lookup because methotrexate's J-code
(J9250 / J9260) is a legitimate chemotherapy code on paper.

---

## The prior commercial-claims study matching strategy (why the prior-study research log has drug names, not HCPCS)

From `../gold_standard_legacy/lung_cancer.sql` lines 7–15:

```
-------- ProcedureCriteriaLungCancer: from prior commercial-claims study HPD directly
-------- PharmacyCriteriaLungCancer: from prior commercial-claims study HPD, processed with
                                     immunotherapy_autoimmunity.R
-------- PharprocCriteriaLungCancer: from prior commercial-claims study HPD, manually searched on
                                     https://www.findacode.com for CPT code
```

The prior commercial-claims study pipeline:

1. Starts with **prior commercial-claims study-provided clinical criteria files** (`ProcedureCriteria`,
   `PharmacyCriteria`) listing drug names / NDCs / CPTs relevant to lung
   cancer.
2. Processes the pharmacy file with an **R preprocessing script**
   (`immunotherapy_autoimmunity.R`) to extract the specific drugs of
   interest.
3. Manually searches [findacode.com](https://www.findacode.com) for the
   HCPCS code of each drug.

The CMS pipeline does the same lookup but from public CMS HCPCS quarterly
data rather than a vendor-supplied file. The agent should use the public
HCPCS source.

---

## Provenance

- prior commercial-claims study chemo drug list (partial, from various context):
  `../gold_standard_legacy/lung_cancer.sql` (references to
  `ProcedureCriteriaLungCancer`, `PharmacyCriteriaLungCancer`,
  `PharprocCriteriaLungCancer` at lines 7-15).
- Methotrexate exclusion: prior-study research log
  `prior-study log NOV2017/nov22.tex:15` (log not in repo; content
  transcribed above).
- Targeted-therapy drug enumeration: prior-study research log
  `prior-study log JUN2017/jun2.tex` (log not in repo).
- Gold-standard benchmark: the published thesis Table C.1 (~28 HCPCS codes).

## Agent-benchmark framing

Given NL prompt *"find patients treated with chemotherapy for lung
cancer"*, the agent should:

1. Enumerate the lung-cancer chemotherapy drug classes: **platinum doublets**
   (cisplatin + carboplatin), **taxanes** (paclitaxel, nab-paclitaxel,
   docetaxel), **antimetabolites** (gemcitabine, pemetrexed), **vinca
   alkaloids** (vinorelbine), **topoisomerase inhibitors** (etoposide,
   irinotecan). This is a clinical-taxonomy lookup (NCCN guidelines for
   NSCLC and SCLC).
2. Map each drug → HCPCS J-code via the CMS HCPCS quarterly release.
3. Add the targeted-therapy anti-angiogenics if in scope (Bevacizumab
   J9035, Ramucirumab J9308).
4. **Exclude methotrexate** even though its HCPCS code is a legitimate
   chemotherapy code — the clinical context of the study (concurrent
   autoimmune analysis) forbids it.

the published thesis Table C.1 is the benchmark. Step 4 is the judgement call
the agent must learn to make from a clinical-context reading of the
prompt, not from HCPCS alone.
