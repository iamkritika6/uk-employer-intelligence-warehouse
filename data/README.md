# Data sources and licences

Raw data files are **not** committed to this repository. `data/raw/` is gitignored.
The publishers below are the authoritative source; download the files yourself
using the links on this page and place them in `data/raw/`.

All details on this page were read from the live publisher pages on
**25 November 2026**. Where a publisher does not state something, this page says so
rather than filling in an assumption.

---

## 1. Register of licensed sponsors: workers

| | |
|---|---|
| Publisher | UK Visas and Immigration (Home Office), published on GOV.UK |
| Publication page | https://www.gov.uk/government/publications/register-of-licensed-sponsors-workers |
| Official title of the publication | "Register of licensed sponsors: workers" |
| File used | `SP_-_Worker_and_Temporary_Worker_Web_Register_-_2026-11-24.csv` |
| Format and size | CSV, 10.4 MB as listed on the page |
| Page last updated | 25 November 2026 |
| Update frequency | The page carries a dated change log of register updates; it does not state a fixed schedule |

**What it contains**, in the publisher's words: a list of organisations licensed to
sponsor workers on the Worker and Temporary Worker routes, including the category of
workers they are licensed to sponsor and their rating.

**Important for interpretation:** this is a register of *organisations*, not a list of
vacancies. A row means an organisation holds a licence, not that it is currently hiring.

### Licence

The GOV.UK page footer states, verbatim:

> All content is available under the Open Government Licence v3.0, except where otherwise stated

- Licence: **Open Government Licence v3.0**
- Licence text: https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/
- The page also carries a "© Crown copyright" line.
- Attribution wording beyond the above: not stated on the page.

Contains public sector information licensed under the Open Government Licence v3.0.

---

## 2. Free Company Data Product (Companies House)

| | |
|---|---|
| Publisher | Companies House |
| Download page | https://download.companieshouse.gov.uk/en_output.html |
| Official product title | "Free Company Data Product" |
| File used | `BasicCompanyDataAsOneFile-2026-11-01.zip` |
| Format and size | ZIP containing CSV, 471 MB as listed on the page |
| Snapshot date | 01/11/2026 |
| Update frequency | Compiled to the end of the previous month; the page states the latest snapshot is updated within 5 working days of the previous month end |
| Field list published by Companies House | https://resources.companieshouse.gov.uk/toolsToHelp/pdf/freeDataProductDataset.pdf (PDF; its embedded metadata shows it was last modified in 2016) |
| Product FAQs | https://resources.companieshouse.gov.uk/infoAndGuide/faq/publicDataProduct.shtml |

**What it contains**, in the publisher's words: a snapshot of basic company data for live
companies on the register. The page also states the snapshot "is provided free of charge
and will not be supported".

Column names used in this project were taken from the header row of the downloaded CSV,
not from the PDF above, because the PDF predates the current file.

### Licence

This one is not clear-cut, and the ambiguity is recorded here deliberately rather than
resolved by assumption:

- The Companies House download page itself states **no licence**: no licence name, no
  copyright line, no attribution wording.
- The Companies House product FAQ page states no licence either.
- https://resources.companieshouse.gov.uk/legal/termsAndConditions.shtml returned a
  19-character stub ("Service information") and states no terms.
- The **data.gov.uk** catalogue record for the same dataset, "Basic Company Data"
  (https://www.data.gov.uk/dataset/4462e41a-7413-4359-97f5-420b6ca5f9c0/basic-company-data),
  publisher Companies House, lists the licence as **Creative Commons Attribution**.

So the only licence statement found for this dataset is the data.gov.uk catalogue
record's "Creative Commons Attribution". Note this is *not* the Open Government Licence,
which is what a reader might reasonably expect from a UK government dataset.

Attribution for this data: Companies House, Free Company Data Product.

---

## Checking these details yourself

Both publisher pages change over time: the register is re-published regularly and the
Companies House snapshot is replaced monthly. If the filenames above no longer appear on
the pages, the publishers have moved on to a newer file. The pipeline records the
filename and snapshot date it loaded, so results can always be traced back to a specific
download.
