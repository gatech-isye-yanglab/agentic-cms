# agentic-cms

A HIPAA-safe multi-agent LLM system for translating natural-language
biomedical research questions into validated SQL pipelines against
CMS Medicaid claims data, paired with a schema-faithful synthetic
Medicaid sandbox (extended from CMS's Synthea-derived public RIF).

## Why

A senior biostatistician produced the diabetes pipeline in
[`pipelines/diabetes/`](pipelines/diabetes/) over six months of
on-and-off work. The bottleneck wasn't analytical reasoning — it was
the tedious middle: era-aware schema crosswalks (MAX vs TAF column
names), ICD-9 ↔ ICD-10 transitions, partition-filter requirements,
cursor-based stored procedures, and per-disease clinical criteria.
A naive LLM agent fails on this immediately. A specialized
multi-agent system with explicit guardrails has a fighting chance.

The HIPAA constraint makes this harder. An agent cannot connect to a
real Medicaid database. The system here keeps all agent activity on
the public side of the trust boundary; a credentialed human reviewer
is the only path that crosses into real PHI.

## What's in here

A HIPAA-safe trust-boundary design as the up-front compliance
prerequisite, plus two research contributions on top:

**Prerequisite — HIPAA-safe trust boundary.** A three-zone design in
which the agent has zero network connection to the real Medicaid
warehouse; a credentialed human reviewer is the sole carrier across
the boundary. Defense-in-depth is codified in
[`knowledge/constraints.py`](knowledge/constraints.py) (partition
Critic, static + live checks),
[`agents/tools/mysql_tools.py`](agents/tools/mysql_tools.py)
(statement-timeout-with-`KILL` tool layer), and
[`synthetic_data/gen_ddl.py`](synthetic_data/gen_ddl.py)
(era-correct partition indexes). See [`docs/hipaa.md`](docs/hipaa.md).

1. **Schema-faithful synthetic CMS Medicaid database, extended from
   Synthea.** 21 tables, 2,533 columns, three-era schema crosswalk
   (MAX 2005–2012 / MAX 2013–2015 / TAF 2016+). Extends CMS's
   Synthea-derived Synthetic RIF 2023 with era-aware reshaping and a
   targeted overlay for treatment-code patterns Synthea doesn't emit
   (oncology J/C codes, diabetes HCPCS). Engineered as a *structural
   test fixture* for agent development — not a distributional
   substitute for real claims. See
   [`docs/synthetic_data.md`](docs/synthetic_data.md).

2. **End-to-end multi-agent prototype + canonical research pipelines.**
   A LangGraph-style ReAct loop today (Azure GPT-4o, two MySQL tools,
   Critic with retry), with the planned 6-node DAG documented in
   [`docs/architecture.md`](docs/architecture.md). Canonical 5-stage
   gold-standard SQL pipelines for diabetes
   ([`pipelines/diabetes/`](pipelines/diabetes/)) and lung cancer
   ([`pipelines/lung_cancer/`](pipelines/lung_cancer/)). A pancreas
   adapter is planned (see
   [`pipelines/pancreas/`](pipelines/pancreas/)).

## Quickstart

The fastest reproducibility path needs only Python and pytest — no
MySQL, no Azure, no external services. **One prerequisite:** two
public CMS datasets (~4 GB total) need to be downloaded into
`synthetic_data/` first. They're not redistributed in this repo.

```bash
# 1. Clone
git clone https://github.com/gatech-isye-yanglab/agentic-cms.git
cd agentic-cms

# 2. Install minimum deps (just pytest)
pip install pytest

# 3. Download the public input datasets — ~4 GB total
#    See synthetic_data/download_synthetic_data.sh and docs/synthetic_data.md
#    for the URLs and expected layout. The build script will emit a clear
#    error if they're missing.

# 4. Build the synthetic CMS database (~2.5 min)
SKIP_MYSQL=1 bash synthetic_data/build_cms_source.sh

# 5. Run the compliance test suite (<1 sec, 25 tests / 83 subtests)
pytest synthetic_data/tests/
```

Expected: `25 passed, 83 subtests passed`.

That gives you a working schema-faithful synthetic CMS database with
21 tables and ~657k rows in `synthetic_data/synthetic_db.sqlite`.

To also run the gold-standard pipelines and the agent demo tests,
you need MySQL on `127.0.0.1:3306` and (for the agent) Azure OpenAI
access. See:

- [`pipelines/diabetes/README.md`](pipelines/diabetes/README.md) —
  diabetes pipeline run.
- [`pipelines/lung_cancer/README.md`](pipelines/lung_cancer/README.md)
  — lung-cancer pipeline run.
- [`tests/README.md`](tests/README.md) — agent prototype demo tests
  (with saved traces from real GPT-4o runs).

Full development install (`pip install -e ".[all]"`) brings in the
LangChain agent stack and `mysql-connector-python`.

## HIPAA model — one-paragraph version

The agent runs only against synthetic data. Real claims data lives
behind a VPN + 2FA + VDI institutional HIPAA enclave; the agent has
zero direct network connection to it. Two human-mediated crossings:
schema metadata (column names + types only) flows out, vetted SQL
text flows in, aggregate result tables flow out under cell-suppression
rules. Defense-in-depth is codified in
[`knowledge/constraints.py`](knowledge/constraints.py),
[`agents/tools/mysql_tools.py`](agents/tools/mysql_tools.py), and
[`synthetic_data/gen_ddl.py`](synthetic_data/gen_ddl.py). The full
trust-boundary diagram, layered controls, and honest gaps are in
[`docs/hipaa.md`](docs/hipaa.md).

## Status

**Early public release** accompanying an AWS Agentic AI grant
proposal (Spring 2026): *"An Engineering Pathway of Agentic AI for
Scalable Medicaid Research."* The schema-faithful synthetic CMS
database and its 25-test compliance harness are complete and
runnable today. The
multi-agent prototype runs as a single ReAct loop driving Azure
GPT-4o (validated end-to-end on Steps 1 and 2 of the diabetes
pipeline; saved traces in [`tests/`](tests/)). The 6-node LangGraph
DAG that splits the Schema / Clinical / SQL Writer / Critic /
Assembler responsibilities into separate nodes is the planned grant
work. The MedSQL-CMS benchmark in
[`benchmark/`](benchmark/) is forthcoming.

## Citation

```bibtex
@software{yang2026agenticcms,
  author = {Yang, Shihao},
  title  = {agentic-cms: Agentic AI for Reproducible Medicaid Research},
  year   = {2026},
  url    = {https://github.com/gatech-isye-yanglab/agentic-cms},
  license = {Apache-2.0}
}
```

See [`CITATION.cff`](CITATION.cff). For related publications that
motivate the methodology, see [`docs/papers.md`](docs/papers.md).

## License

Apache-2.0. See [`LICENSE`](LICENSE).

## Acknowledgments

- [Synthea](https://github.com/synthetichealth/synthea) — the open-source synthetic-EHR engine that seeds the TAF claims in [`synthetic_data/`](synthetic_data/).
- [CMS Synthetic RIF 2023](https://data.cms.gov/collection/synthetic-medicare-enrollment-fee-for-service-claims-and-prescription-drug-event) — the public claims dataset the TAF tier loads.
- [DE-SynPUF](https://www.cms.gov/data-research/statistics-trends-and-reports/medicare-claims-synthetic-public-use-files/cms-2008-2010-data-entrepreneurs-synthetic-public-use-file-de-synpuf) — the 5% Medicare sample used as the bootstrap pool for MAX-era beneficiaries.
- [PhecodeX v1.0](https://github.com/PheWAS/PhecodeXVocabulary) — the disease-anchor vocabulary that drives the cohort-identification recipe in [`cohort_identification/`](cohort_identification/).
- AWS Bedrock AgentCore — intended deployment target for the multi-agent prototype.
