# agentic-cms — CLAUDE.md

## What this project is

HIPAA-safe multi-agent LLM system for translating natural-language
biomedical research questions into validated SQL pipelines against
CMS Medicaid claims data, paired with a schema-faithful
synthetic Medicaid sandbox. See [README.md](README.md) for the
public-facing pitch.

## Hard rules

- The agent runs ONLY against synthetic data
  ([synthetic_data/](synthetic_data/) or
  [toy_db/](toy_db/)). Never connect agent code to real CMS claims
  data.
- No PHI, no real beneficiary identifiers, no `.env` files, no
  credentials in this repo. See [.gitignore](.gitignore).
- All SQL the agent generates against real institutional data must be
  reviewed and executed by a credentialed human researcher inside the
  HIPAA enclave. The agent NEVER touches real data directly.
- Partition-filter rule: every query against `cms_source.*` must
  include `state_key` AND a year filter (`YR_NUM` for MAX,
  `RFRNC_YR` for TAF). The Critic
  ([knowledge/constraints.py](knowledge/constraints.py)) enforces
  this; do not bypass.

## File layout

- [synthetic_data/](synthetic_data/) — schema-faithful synthetic CMS
  database generator. Run
  `SKIP_MYSQL=1 bash synthetic_data/build_cms_source.sh` to (re)build
  the SQLite artifact + `pytest synthetic_data/tests/` to validate.
- [agents/](agents/) — multi-agent prototype. Today a single
  ReAct-style loop driven from
  [tests/test_minimal_extraction.py](tests/test_minimal_extraction.py);
  see [agents/README.md](agents/README.md) for the planned 6-node
  DAG.
- [knowledge/](knowledge/) — schema metadata, partition-filter
  constraints, skill files, disease profiles.
- [cohort_identification/](cohort_identification/) — public-data
  PheWAS / ICD / HCPCS / NDC reference scaffolding for the
  cohort-lookup recipe.
- [pipelines/](pipelines/) — canonical 5-stage gold-standard SQL
  pipelines for diabetes and lung cancer; pancreas adapter is
  forthcoming.
- [toy_db/](toy_db/) — small MySQL fixture for the agent prototype's
  smoke tests.
- [tests/](tests/) — agent demo runs + saved traces from real
  GPT-4o sessions.
- [benchmark/](benchmark/) — MedSQL-CMS benchmark scaffolding
  (forthcoming).
- [docs/](docs/) — architecture, HIPAA model, synthetic-data design,
  related papers.

## Common commands

- Build synthetic DB (no MySQL needed):
  `SKIP_MYSQL=1 bash synthetic_data/build_cms_source.sh`
- Test synthetic DB:
  `pytest synthetic_data/tests/`
- Seed the small MySQL fixture for agent tests:
  `python3 toy_db/seed_mysql.py && python3 toy_db/run_sql.py`
- Run the diabetes pipeline end-to-end:
  `bash pipelines/diabetes/run_pipeline.sh`
- Run the lung-cancer pipeline end-to-end:
  `bash pipelines/lung_cancer/run_pipeline.sh`
- Run the agent demo (needs Azure GPT-4o + populated MySQL):
  `python3 tests/test_minimal_extraction.py`

## Style notes

- Public-facing prose: clear, terse, no internal jargon.
- Code: keep as-is. It's already public-grade. Don't refactor for
  refactor's sake.
- Commit messages: short, focused on what changed and why.
- New disease pipelines: model on
  [pipelines/diabetes/](pipelines/diabetes/) and
  [pipelines/lung_cancer/](pipelines/lung_cancer/) — same 5-stage
  shape, swap the disease profile in
  [knowledge/diseases/](knowledge/diseases/).
