# UK Employer Intelligence Warehouse

Employer and labour-market analytics on UK open data, built as a PostgreSQL warehouse
with layered SQL transformations.

**Status: in progress.** This README is filled in as each layer is built and run. Every
number that appears here will come from running the code in this repository; nothing is
stated before it has been measured.

## What this project does

Two UK open datasets are loaded into PostgreSQL and modelled into a star schema so that
questions about employers can be answered with SQL:

1. A register of organisations licensed to sponsor workers, published by the Home Office
   on GOV.UK.
2. The Companies House Free Company Data Product, a monthly snapshot of basic data for
   live companies on the register.

The two are linked on organisation name, which allows register entries to be enriched
with company attributes such as SIC codes, registered address and incorporation date.
Name matching is imperfect; the measured match rate and an estimate of false matches will
be reported here once the matching step has been run.

Full source details, publisher pages and licence terms are in
[`data/README.md`](data/README.md). Raw data files are not committed.

## Layers

| Schema | Purpose |
|---|---|
| `raw` | Loaded exactly as downloaded, every column as text, no cleaning |
| `staging` | Typed and cleaned, organisation names normalised for matching |
| `marts` | Star schema: dimensions, a fact table and a match table |
| `analysis` | One query per business question |

## Stack

- PostgreSQL 16 in Docker
- Plain `.sql` files for all transformations
- Python only to orchestrate: connect, run the SQL files in order, print results
- `pg_trgm` extension for fuzzy name matching

## How to run

To be written once the pipeline runs end to end.

## Author

Kritika Singh Chauhan
