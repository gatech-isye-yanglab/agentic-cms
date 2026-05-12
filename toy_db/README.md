# toy_db — Small MySQL Fixture for Agent Demo Tests

A tiny ~1,400-row MySQL fixture used to drive the agent prototype's
smoke tests in [`../tests/`](../tests/). **This is a different artifact
from the schema-exact synthetic CMS sandbox in
[`../synthetic_data/`](../synthetic_data/)** — they exist for different
reasons:

| Folder | Purpose | Scale |
|---|---|---|
| `synthetic_data/` | Schema-exact public synthetic CMS Medicaid sandbox. The headline contribution: same column names, same partition rules, same era distinctions as the institutional database. Used by anyone running cohort pipelines. | ~116k beneficiaries, ~657k rows |
| `toy_db/` (this folder) | Compact MySQL fixture tuned to drive the agent's smoke tests in seconds — small enough that the GPT-4o ReAct loop terminates in <60 s and doesn't burn Azure credits. | 1,000 patients, ~1,400 claim rows, 13 states × 14 years |

Both fixtures use the identifier-exact `cms_source` schema (`patient_id`,
`BENE_ID`, `state_key`, `YR_NUM`, `RFRNC_YR`, `DIAG_CD_*`, `DGNS_CD_*`,
etc.) so SQL written against one runs against the other.

## What's here

| File | Purpose |
|---|---|
| `seed_mysql.py` | Creates the 6 source tables + 2 meta tables in `cms_source` and inserts 1,000 synthetic patient claims tuned to exercise the diabetes-pipeline filtering logic (40% positive / 20% single-claim / 15% long-gap / 10% wrong-state / 10% no-diabetes / 5% ambiguous-demographics). |
| `run_sql.py` | Loads the diabetes pipeline's reference + Step-2 + Step-3 + Step-4 SQL from [`../pipelines/diabetes/`](../pipelines/diabetes/) into the populated `cms_source`. After this runs, the agent tests in [`../tests/`](../tests/) have everything they need. |

## Usage

```bash
# 1. Prerequisites: Python deps + MySQL on localhost:3306 with cms_source DB
pip install mysql-connector-python
mysql -u root -e "CREATE DATABASE IF NOT EXISTS cms_source;"

# 2. Seed source tables + synthetic claims
python3 toy_db/seed_mysql.py

# 3. Load reference + Step-2/3/4 SQL
python3 toy_db/run_sql.py

# 4. Run the agent demo tests (needs Azure GPT-4o credentials; see ../README.md)
python3 tests/test_minimal_extraction.py
python3 tests/test_step1_and_2.py
```

## Why the bucket distribution

`seed_mysql.py` allocates patients into six buckets designed to exercise
each branch of the gold-standard filtering logic:

| Bucket | % | Agent should… |
|---|---|---|
| `positive` | 40% | …keep these (≥2 claims <730 days apart in an SE state) |
| `single` | 20% | …drop these (only 1 claim, fails 24-month rule) |
| `long_gap` | 15% | …drop these (2 claims but >730 days apart) |
| `wrong_state` | 10% | …drop these (claims outside AL/FL/GA/MS/NC/SC/TN) |
| `no_diabetes` | 10% | …no-op (non-diabetes ICD codes) |
| `ambiguous` | 5% | …flag these (sex toggles across claims) |

If the agent's generated SQL handles all six correctly, the final cohort
size matches `seed_mysql.py`'s expected `positive` count.
