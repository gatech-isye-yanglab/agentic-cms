# Immunotherapy HCPCS codes — recovered benchmark (legacy commercial-claims source)

**Status.** The CMS-side `<scratch_db>.immuno_cpt_codes` table was purged from
the institutional VM. The PI's prior commercial-claims lung-cancer study
independently arrived at essentially the same HCPCS set by manual search at
[findacode.com](https://www.findacode.com).

Both the prior commercial-claims study and the CMS pipeline converge on the same short list of HCPCS codes
because these are the only FDA-approved immune-checkpoint-inhibitor J-codes
(and their pre-approval C-codes) during the 2014–2018 window both studies
cover.

---

## The authoritative prior-study list (as of March 4, 2018)

From `../gold_standard_legacy/lung_cancer.sql:14`:

```
effectively only C9453, J9299, C9027, J9271 as of Mar 4, 2018
```

These four codes cover the two lung-cancer immunotherapy drugs that had
meaningful claims volume at study cutoff:

| HCPCS | Drug (generic / trade) | Target | Notes |
|---|---|---|---|
| **J9299** | Nivolumab / Opdivo | PD-1 | Primary J-code, active after FDA approval |
| **C9453** | Nivolumab / Opdivo | PD-1 | Pre-approval / emerging C-code for same drug |
| **J9271** | Pembrolizumab / Keytruda | PD-1 | Primary J-code, active after FDA approval |
| **C9027** | Pembrolizumab / Keytruda | PD-1 | Pre-approval / emerging C-code for same drug |

The `C` prefix denotes the temporary CMS HCPCS C-code assigned before the
drug receives its permanent J-code; both codes refer to the same NDC and
must both be searched to catch early-adopter claims.

---

## The fuller CMS list (the published thesis Table 4.2)

The published thesis enumerates six J-codes plus six C-codes, because the CMS
pipeline's window extends further and includes CTLA-4 and PD-L1 inhibitors
with very low lung-cancer volume:

| HCPCS | Drug (generic / trade) | Target |
|---|---|---|
| J9228 | Ipilimumab / Yervoy | CTLA-4 |
| J9299 | Nivolumab / Opdivo | PD-1 |
| J9271 | Pembrolizumab / Keytruda | PD-1 |
| J9022 | Atezolizumab / Tecentriq | PD-L1 |
| J9173 | Durvalumab / Imfinzi | PD-L1 |
| J9023 | Avelumab / Bavencio | PD-L1 |
| C9027, C9284, C9453, C9483, C9491, C9492 | (pre-approval C-codes for the same drugs) | — |

Ipilimumab appears in the prior-study research log via NDC text match
(`prior-study log MAY2017/may31.tex:15`: `WHERE P.NdcDescription LIKE
'%yervoy%'`) and via `C9284 / J9228` in the prior-study category lookup
(`prior-study log MAY2017/may10.tex:43-44, 60-61, 77-78`) — so it is in
scope for the prior commercial-claims study as well; it just does not appear in the core
four-code list because lung-cancer volume was small. (The prior-study LaTeX
research log is not included in this repo; content relevant to the gold
standard has been transcribed into this file.)

---

## Drug → HCPCS pattern (what the agent must learn)

The general move is: given a **drug class** (here: "immune checkpoint
inhibitor"), produce the HCPCS list via:

1. **Enumerate the drugs in the class.** FDA-approved PD-1 / PD-L1 /
   CTLA-4 inhibitors. This is a clinical-taxonomy lookup (DrugBank, FDA
   label database, ATC code system).
2. **Map each drug → HCPCS.** The drug-name → J-code mapping lives in the
   **CMS HCPCS quarterly release** (free download, see
   `../../../../icd_code_reference/databases/hcpcs/`). The prior commercial-claims study
   did this by keyword search at `findacode.com` (line 13 of
   `lung_cancer.sql`); the agent should use the HCPCS quarterly file
   directly.
3. **Also include pre-approval C-codes.** For any drug in the class that
   was approved within the study window, its pre-approval C-code must be
   included or early claims (2014–2015 for nivolumab/pembrolizumab) will
   be missed. The HCPCS quarterly file records C→J transitions.
4. **NDC-level fallback for pharmacy claims.** Pharmacy claims may carry
   NDC rather than HCPCS; the prior commercial-claims study does an `NdcDescription LIKE
   '%yervoy%'` style match to recover those (see
   `prior-study log MAY2017/may31.tex` for the `%yervoy%` pattern and
   `prior-study log JUN2017/jun2.tex:37-44` for the full drug-name
   enumeration used in NDC text matching: YERVOY, PEMBROLIZUMAB,
   NIVOLUMAB, ATEZOLIZUMAB, AVELUMAB, DURVALUMAB, IPILIMUMAB).

Step 3 (pre-approval C-codes) is the subtle one — it is the reason the
list contains twelve HCPCS values rather than six, and is the kind of
domain detail that would be easy for a naive agent to miss.

---

## Provenance

- prior commercial-claims paper canonical 4-code list:
  `../gold_standard_legacy/lung_cancer.sql:14`
- Prior-study Ipilimumab evidence (from prior-study research log, not in repo):
  - `prior-study log MAY2017/may10.tex:43-44, 60-61, 77-78` (HCPC J9228
    and CPT4 C9284 in specialty-category lookup)
  - `prior-study log MAY2017/may31.tex:15` (NDC `LIKE '%yervoy%'`)
- Prior-study full drug list for NDC matching (from prior-study research log,
  not in repo): `prior-study log JUN2017/jun2.tex:37-44`
- CMS pipeline list: the published thesis Table 4.2.

## Agent-benchmark framing

Given NL prompt *"find patients treated with immunotherapy for lung
cancer"*, the agent should output the 4-code short list (Nivolumab +
Pembrolizumab with their pre-approval C-codes) if the intent matches the
prior commercial-claims study, or the 12-code long list if the intent matches the gold-standard author's CMS
study. The agent must understand the taxonomy (immune checkpoint inhibitor
vs. specifically PD-1) and the year window (pre/post pembrolizumab approval)
to pick between them.
