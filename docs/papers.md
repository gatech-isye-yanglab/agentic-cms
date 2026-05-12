# Related Publications

Links to the peer-reviewed papers and preprints that motivate or
back this artifact. We do not redistribute PDFs in this repository —
follow the links below for the publishers' canonical copies.

## Peer-reviewed

**Wang, Yang, et al.** *"A statistical method for analyzing
multi-cancer prevention efficacy of repurposed drugs."* **NPJ
Precision Oncology** (2021). PMID: [34508179](https://pubmed.ncbi.nlm.nih.gov/34508179/).

**Yang, et al.** *"Methodological considerations in claims-based
cohort identification for autoimmune adverse events."* **Clinical
Pharmacology & Therapeutics** (2019). PMID: [31356677](https://pubmed.ncbi.nlm.nih.gov/31356677/).

## Preprints

**Sun, Yang.** *"Immunotherapy-induced autoimmune adverse events in
lung cancer: a CMS Medicaid cohort study."* **medRxiv** (2024).
DOI: [10.1101/2024.12.03.24318450](https://doi.org/10.1101/2024.12.03.24318450).
PMC: [PMC11643146](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11643146/).

## How these relate to the artifact

- The 2019 *Clinical Pharmacology & Therapeutics* paper is the sole
  peer-reviewed evidence that the methodology underlying
  [`pipelines/lung_cancer/`](../pipelines/lung_cancer/) produces
  publication-quality cohort-level claims research. It used an
  earlier commercial-claims schema (not CMS Medicaid) but the same
  PheWAS-anchored cohort-identification recipe documented in
  [`cohort_identification/architecture_proposal.md`](../cohort_identification/architecture_proposal.md).

- The 2021 *NPJ Precision Oncology* paper applied a related
  statistical method on a different claims source.

- The 2024 medRxiv preprint extends the 2019 methodology to the
  CMS Medicaid TAF / MAX schema and is the closest published
  description of the lung-cancer + autoimmune pipeline shipped under
  [`pipelines/lung_cancer/`](../pipelines/lung_cancer/).
