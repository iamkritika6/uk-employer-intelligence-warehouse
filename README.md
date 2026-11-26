# UK Employer Intelligence Warehouse

A PostgreSQL data warehouse built from two UK open datasets, modelling licensed
employers into a star schema and linking them to company records so questions
about employer location, sector, size and age can be answered in SQL.

Every number on this page was produced by running the code in this repository
against the data described below. Where something could not be measured, this
page says so rather than estimating.

**Snapshot used throughout: the register published 2026-10-15 and the Companies
House snapshot dated 2026-11-01.**

---

## What it does

| | |
|---|---|
| Register rows loaded | 143,220 |
| Company rows loaded | 5,711,779 |
| Employers modelled | 126,963 |
| Fact rows | 142,356 |
| Employer names linked to a company | 80.66% |
| Quality checks passing | 18 of 18 |

Two sources are loaded as text, cleaned and typed in a staging layer, linked to
each other by organisation name, and modelled into a star schema. Analysis
queries then answer nine questions against the marts layer.

---

## Data sources and licences

Raw data files are **not** committed; `data/raw/` is gitignored. Download them
yourself from the pages below. Full detail, including exactly what each
publisher does and does not state, is in [`data/README.md`](data/README.md).

**1. Register of licensed sponsors: workers** — published by UK Visas and
Immigration on GOV.UK.
https://www.gov.uk/government/publications/register-of-licensed-sponsors-workers

The GOV.UK page footer states, verbatim: *"All content is available under the
Open Government Licence v3.0, except where otherwise stated"*, linking to
https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/, with
a "© Crown copyright" line.

> Contains public sector information licensed under the Open Government Licence v3.0.

**2. Free Company Data Product** — published by Companies House.
https://download.companieshouse.gov.uk/en_output.html

The licence here is genuinely unclear, and that is recorded rather than
resolved. The Companies House download page states no licence; neither does
its product FAQ; its terms-and-conditions page returns a 19-character stub. The
**data.gov.uk** catalogue record for the same dataset lists the licence as
**Creative Commons Attribution** — notably *not* the Open Government Licence
that a UK government dataset might be assumed to carry.

---

## Architecture

```
data/raw/  (gitignored)
    |
    |  COPY, text columns only, nothing cleaned
    v
raw.licensed_employers          raw.companies
    |                                |
    |  trim, type, split, normalise names
    v                                v
staging.stg_licensed_employers  staging.stg_companies
    |                                |
    +---------- matching ------------+
    |     exact, then pg_trgm fuzzy
    v
marts.employer_company_match
    |
    v
marts.dim_employer   marts.dim_location   marts.dim_company
                \            |            /
                 v           v           v
                 marts.fact_employer_snapshot
                            |
                            v
                 marts.employer_history  (SCD Type 2)
                            |
                            v
                   sql/50_analysis/*.sql
```

Entity relationship diagram, with every column and key:
[`docs/erd/erd.md`](docs/erd/erd.md).

**Why four schemas.** `raw` is never edited, so any number can be traced back to
the file it came from. `staging` holds nothing of its own and can be rebuilt
from `raw`. `marts` is the model. Keeping them apart is what makes a wrong
figure diagnosable instead of mysterious.

---

## Stack

- PostgreSQL 16.16, run in Docker
- Plain `.sql` files for every transformation
- Python 3.15.2 for orchestration only — standard library, no third-party packages
- `pg_trgm` for fuzzy name matching

---

## How to run (Windows PowerShell)

**Prerequisites:** Docker Desktop running, and Python 3 available as `py`.

```powershell
cd C:\Users\Kritika\repos\uk-employer-intelligence-warehouse
```

```powershell
Copy-Item .env.example .env
```

Edit `.env` and set `POSTGRES_PASSWORD` to any local value. `.env` is gitignored.

```powershell
docker compose up -d
```

Download both files into `data/raw\` from the pages in the Data sources section
above. Leave the Companies House file unzipped as a `.csv`.

```powershell
py scripts\run_pipeline.py --dry-run
```

```powershell
py scripts\run_pipeline.py
```

Useful flags: `--skip-raw` skips reloading the source files, `--only staging`
runs a single layer.

**Expect the full run to take around 30 minutes**, dominated by the fuzzy
matching pass. Measured on the machine this was built on:

| Step | Time |
|---|---|
| Load 5.7m company rows | 2 min 37 s |
| Build staging companies | 1 min 56 s |
| Trigram index build | 23 s |
| Fuzzy matching pass | 18 min 31 s |
| Build fact table | 1 min 14 s |

Run the analysis queries individually:

```powershell
docker exec -i uk_employer_intel_pg psql -U employer_intel -d employer_intel -f - < sql\50_analysis\01_employers_by_town.sql
```

Run the SCD2 test:

```powershell
docker exec -i uk_employer_intel_pg psql -U employer_intel -d employer_intel -f - < tests\test_scd2_snapshots.sql
```

---

## Business questions and results

All results below come from the 2026-10-15 register snapshot. Query files are in
[`sql/50_analysis/`](sql/50_analysis/), one question per file with the question
written at the top.

### 1. Which towns have the most registered employers?

Geography is extraordinarily concentrated.

| Rank | Town | Employers | % of total | Cumulative |
|---|---|---|---|---|
| 1 | London | 36,462 | 28.59% | 28.59% |
| 2 | Birmingham | 3,061 | 2.40% | 30.99% |
| 3 | Manchester | 2,859 | 2.24% | 33.23% |
| 4 | Leicester | 1,402 | 1.10% | 34.33% |
| 5 | Glasgow | 1,368 | 1.07% | 35.40% |

London alone holds **28.59%** of all registered employers.

### 2. Where are technology-sector employers located?

"Technology" means SIC divisions 26, 61, 62, 63 and group 582. The definition
lives in a table, with the borderline divisions that were *excluded* and the
reason for each:
[`sql/50_analysis/00_technology_sic_definition.sql`](sql/50_analysis/00_technology_sic_definition.sql).

| Rank | Town | Tech employers | All employers | % of town |
|---|---|---|---|---|
| 1 | London | 4,760 | 36,462 | 13.1% |
| 2 | **Reading** | 259 | 904 | **28.7%** |
| 3 | Manchester | 248 | 2,859 | 8.7% |
| 4 | Birmingham | 185 | 3,061 | 6.0% |
| 6 | Cambridge | 144 | 835 | 17.2% |

London leads on volume, but **Reading has more than double London's
concentration**: 28.7% of its registered employers are technology companies.

### 3. Ranking within London, Berkshire and Reading

| Area | Rank | Town | Tech employers | % of area |
|---|---|---|---|---|
| Berkshire | 1 | Reading | 95 | 50.5% |
| Berkshire | 2 | Slough | 24 | 12.8% |
| Berkshire | 3 | Maidenhead | 21 | 11.2% |
| London | 1 | London | 126 | 80.8% |
| Reading | 1 | Reading | 139 | 100.0% |

Reading accounts for **half of Berkshire's** technology employers.

Note, because the output is easy to misread: Reading is *in* Berkshire, so these
areas overlap. `CASE` stops at its first matching branch, so Reading addresses
whose county reads "Berkshire" are counted there, and the "Reading" area holds
the rest. Explained in the query file.

### 4. How are ratings distributed?

| Employer type | Licences | A | B | A (variant) | % B |
|---|---|---|---|---|---|
| Worker | 136,750 | 136,553 | 97 | 5 | 0.071% |
| Temporary Worker | 5,606 | 5,603 | 1 | 2 | 0.018% |

B ratings are vanishingly rare: **98 of 142,356 licences**.

### 5. How concentrated is the register?

| Decile of towns | Towns | Employers | % of employers |
|---|---|---|---|
| 1 (largest) | 681 | 112,745 | **88.39%** |
| 2 | 681 | 6,746 | 5.29% |
| 3 | 681 | 2,533 | 1.99% |
| 10 (smallest) | 680 | 680 | 0.53% |

The top tenth of towns holds **88.39%** of employers. The bottom six deciles
have exactly one employer each.

### 6. How old are the companies behind these employers?

| Age band | Employers | % | Cumulative |
|---|---|---|---|
| 0–1 years | 2,383 | 2.40% | 2.40% |
| 2–4 years | 15,958 | 16.08% | 18.48% |
| 5–9 years | 29,868 | 30.09% | 48.57% |
| 10–19 years | 30,094 | 30.32% | 78.89% |
| 20–49 years | 18,537 | 18.68% | 97.57% |
| 50+ years | 2,411 | 2.43% | 100.00% |

Nearly half are under ten years old.

### 7. Incorporations by year

Peak year 2020 (6,484). **The sharp fall after 2023 is not a decline** — it is
an artefact. This shows incorporation years of companies on the register
*today*, and a company formed in 2026 has had almost no time to obtain a
licence. The caution is written into the query file so the figures cannot be
misread later.

### 8. How many routes does an employer hold?

| Routes | Employers | % |
|---|---|---|
| 1 | 114,019 | 89.80% |
| 2 | 11,515 | 9.07% |
| 3 | 1,272 | 1.00% |
| 4 | 147 | 0.12% |
| 5 | 9 | 0.01% |
| 6 | 1 | 0.00% |

One employer — BMW (UK) Holdings Limited — holds six.

### 9. Leading sector by town

| Town | Leading sector | Employers | % of town |
|---|---|---|---|
| London | Other business support service activities n.e.c. | 1,701 | 5.8% |
| Reading | Information technology consultancy activities | 103 | 14.4% |
| Slough | Information technology consultancy activities | 70 | 9.5% |
| Cambridge | Software development **and** biotechnology research (tie) | 61 each | 9.3% |

---

## Matching method and measured match rate

Organisation names are normalised identically on both sides — lowercased,
ampersands spelled out, punctuation replaced with spaces, whitespace collapsed,
legal suffixes (Ltd, Limited, PLC, LLP…) stripped — then matched in two passes.

| Method | Names | % |
|---|---|---|
| Exact | 99,099 | 78.05% |
| Fuzzy (`pg_trgm`, ≥ 0.80) | 3,311 | 2.61% |
| Ambiguous | 613 | 0.48% |
| No match | 23,940 | 18.86% |

**80.66% matched overall.**

**Ambiguous names are deliberately left unmatched.** 613 names are shared by two
to five different companies. Picking the first would have raised the rate to
78.53% and attached employers to the wrong company.

**23,940 matched nothing, and that is largely correct.** NHS trusts,
universities, schools and councils are not registered companies and do not
appear in Companies House at all.

### How wrong is the fuzzy matching?

A sample of 24 fuzzy matches was read side by side and judged by inspection:
**12 correct, 5 wrong, 7 uncertain**. So **at least 21% of fuzzy matches are
wrong**, possibly up to 50% — roughly 700 to 1,650 incorrect links. Full sample
with verdicts: [`docs/match_sample_check.md`](docs/match_sample_check.md).

This is a judgement by eye, not verified ground truth. No authoritative list
exists saying which register entry belongs to which company.

**A similarity score of 1.000 does not mean the match is correct.** Of the 208
fuzzy matches scoring a perfect 1.000, **166 are the same words in a different
order**:

```
taylor thomas                              <->  thomas taylor
tierra and mar                             <->  mar and tierra
centre for economic and business research  <->  centre for business and economic research
```

Trigram similarity compares sets of three-character sequences, so reordering
whole words barely changes the score. Analysis queries that use company
attributes therefore filter to exact matches only.

---

## Data quality results

[`sql/60_quality/01_quality_checks.sql`](sql/60_quality/01_quality_checks.sql)
prints PASS or FAIL with the numbers behind each check. Latest run: **18 PASS,
0 FAIL**, covering row reconciliation between every layer, referential
integrity, grain uniqueness, key uniqueness, date validity and the town-case
rule.

Reported as INFO rather than failures, because they are expected to be
non-zero:

| | |
|---|---|
| Companies with no SIC code (published as the text `None Supplied`) | 231,826 |
| Employer names with no company match | 23,940 |
| Fuzzy matches (≥ 21% expected wrong) | 3,311 |
| Fact rows collapsed from duplicate published rows | 854 |
| Fact rows with contradictory published ratings | 1 |

### Three problems found in the published data

**1. 772 groups of duplicate rows.** The register publishes the same
organisation, town and route two or three times — Avon Cosmetics Limited in
Northampton appears three times on Skilled Worker. 779 surplus rows.

**2. A contradiction.** Easteden Ltd in Omagh is published with **both an A and
a B rating** for the same route. The fact table records this with a
`has_rating_conflict` flag rather than silently choosing one. It was only
visible because the two rows used different spellings of "Omagh".

**3. Four spellings of London.** `London`, `LONDON`, `london` and `lONDON`.
Case-folding reduced 8,100 distinct towns to 6,352. Before this was found, every
town ranking was wrong.

---

## Performance experiment

Reproducible script:
[`sql/70_performance/01_index_experiments.sql`](sql/70_performance/01_index_experiments.sql).
It drops each index, measures, rebuilds, and measures again.

### Experiment 1 — trigram GIN index

Finding companies whose normalised name is similar to a given name: the query
the fuzzy pass runs 27,251 times.

| | Plan | Execution time |
|---|---|---|
| Before | Parallel Seq Scan | 5,031 ms |
| After | Bitmap Index Scan | **56 ms** |

Roughly **90× faster**. Index build 23 s, size 204 MB.

This index is not a refinement — without it the pass would take approximately
**37 hours** instead of 19 minutes.

### Experiment 2 — B-tree index on `company_status`, and a wrong prediction

**Predicted before running: no improvement.** 91% of rows have status `Active`,
and the usual rule is that an index is ignored when a query touches most of a
table.

| | Plan | Execution time |
|---|---|---|
| Before | Parallel Seq Scan | 357 ms |
| After | Parallel Index Only Scan | **169 ms** |

**The prediction was wrong.** That rule assumes the index locates rows and then
fetches them from the table. Here nothing from the table is needed — the query
only counts, and `company_status` is in the index, so PostgreSQL reads the 38 MB
index and never touches the 2.7 GB table. Low selectivity did not matter because
the heap was never visited.

For contrast, the same index against a selective value (`RECEIVERSHIP`, 182
rows): **0.062 ms**.

---

## Limitations

**The register lists organisations, not vacancies.** A row means an organisation
holds a licence, not that it is hiring. Nothing here measures demand for labour.

**Fuzzy matching is unreliable.** At least 21% of the 3,311 fuzzy matches are
wrong. A perfect similarity score is not evidence of correctness, because
trigram similarity is nearly blind to word order.

**Only one snapshot has been loaded.** The SCD Type 2 history in
`marts.employer_history` therefore contains one version per fact row. The logic
is proven by a labelled fixture in [`tests/`](tests/), which covers employers
that are unchanged, changed, removed and newly added, and passes all 10
assertions including idempotency. **Real change history needs a second weekly
download** — the pipeline already finds and applies every register file in
`data/raw` in publication order, so no code change is required.

**19% of employers could not be linked to a company**, so any analysis using
company attributes — sector, age, address — describes the matched subset, not
the whole register.

**County is unusable as geography.** It is blank in 95,020 of 143,220 register
rows. Town is used instead, and no region column was derived, because the
register publishes none and inventing one from town names would be guesswork
presented as data.

**An employer moving town is recorded as a removal and an addition.** Location
is part of the SCD2 business key, because 796 employer/route pairs are published
at more than one town simultaneously. Telling a genuine relocation from a second
site is not possible from this data.

**SIC codes are missing for 231,826 companies**, published as the literal text
`None Supplied`. Those companies cannot be classified by sector.

---

## Repository layout

```
docker-compose.yml          PostgreSQL 16, named volume, data/raw mounted read-only
.env.example                committed template; .env is gitignored
requirements.txt            no third-party packages, and why
scripts/run_pipeline.py     runs everything in order
sql/00_raw/                 schemas, extension, raw tables (text only)
sql/10_staging/             typed, cleaned, name normalisation
sql/20_marts/               star schema with keys and constraints
sql/30_matching/            exact then fuzzy matching
sql/40_snapshots/           SCD Type 2 history and its load function
sql/50_analysis/            nine questions, one file each
sql/60_quality/             PASS/FAIL checks
sql/70_performance/         index experiments
tests/                      SCD2 fixture and assertions
docs/erd/                   entity relationship diagram
docs/match_sample_check.md  hand-checked fuzzy match sample
data/README.md              sources, licences, what each publisher states
```

---

## Author

Kritika Singh Chauhan
