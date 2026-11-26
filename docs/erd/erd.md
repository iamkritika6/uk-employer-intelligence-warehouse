# Entity relationship diagram

The marts layer. Raw and staging tables are deliberately not shown: they are
intermediate working tables, not a model, and including them would obscure the
star.

```mermaid
erDiagram
    DIM_EMPLOYER ||--o{ FACT_EMPLOYER_SNAPSHOT : "licensed as"
    DIM_LOCATION ||--o{ FACT_EMPLOYER_SNAPSHOT : "published at"
    DIM_COMPANY  |o--o{ FACT_EMPLOYER_SNAPSHOT : "linked to"
    DIM_EMPLOYER ||--o{ EMPLOYER_HISTORY : "versioned as"
    DIM_LOCATION ||--o{ EMPLOYER_HISTORY : "at"

    DIM_EMPLOYER {
        int  employer_key PK
        text organisation_name_normalised UK "business key"
        text display_name "most published spelling"
        int  name_variant_count
    }

    DIM_LOCATION {
        int     location_key PK
        text    town_key "case-folded, the real identity"
        text    county_key
        text    town "most published spelling"
        text    county
        int     spelling_count
        boolean is_unknown "one row: town not stated"
    }

    DIM_COMPANY {
        int     company_key PK
        text    company_number UK
        text    company_name
        text    company_category
        text    company_status
        date    incorporation_date
        text    post_town
        text    county
        text    post_code
        text    sic_code_1
        text    sic_description_1
        text    match_method "exact or fuzzy"
        numeric similarity_score
    }

    FACT_EMPLOYER_SNAPSHOT {
        bigint  employer_snapshot_key PK
        int     employer_key FK
        int     location_key FK
        int     company_key FK "nullable: 19% unmatched"
        text    employer_type
        text    rating
        text    route
        date    snapshot_date
        text    source_file
        int     source_row_count "duplicates collapsed"
        boolean has_rating_conflict
    }

    EMPLOYER_HISTORY {
        bigint  employer_history_key PK
        int     employer_key FK
        text    route
        int     location_key FK
        text    employer_type
        text    rating
        date    valid_from
        date    valid_to "9999-12-31 while current"
        boolean is_current
    }

    EMPLOYER_COMPANY_MATCH {
        text    organisation_name_normalised PK
        text    company_number "null when unmatched"
        text    match_method "exact, fuzzy, ambiguous, none"
        numeric similarity_score
        int     candidate_count
    }
```

## Reading the diagram

**`FACT_EMPLOYER_SNAPSHOT` is the centre.** Its grain is one row per employer,
per route, per location, per snapshot, and that grain is enforced by a unique
constraint rather than only described.

**`DIM_COMPANY` is optional** (`|o`). Only 80.66% of employer names matched a
company, so most analysis must survive a null `company_key`. Any query that
inner-joins to `dim_company` is silently answering a question about the matched
subset, which is why the analysis queries say so in their comments.

**`EMPLOYER_COMPANY_MATCH` is not joined to the star.** It is the record of how
matching went, including the names that matched nothing, and it exists so the
match rate can be reported. The star consumes its results through
`dim_company`.

**`EMPLOYER_HISTORY` is the SCD Type 2 table**, keyed on
(employer_key, route, location_key). It currently holds one version per fact
row because only one snapshot has been loaded; a second published snapshot is
what would make it a history.
