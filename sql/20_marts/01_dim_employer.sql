-- dim_employer: one row per organisation on the register.
--
-- Grain: one row per distinct normalised organisation name.
--
-- The normalised name is the business key - the thing that identifies an
-- employer across snapshots and across the two sources. employer_key is a
-- surrogate key: a meaningless integer that the fact table points at. Facts
-- join on a small integer rather than on a long text name, and if the
-- normalisation rules ever change, the surrogate key stays stable.
--
-- display_name is the spelling shown to a human. The register writes the same
-- organisation several ways ("VS Food and Wine", "VS FOOD AND WINE",
-- "VS Food & Wine"), so the most frequently published spelling is chosen
-- rather than an arbitrary one.

DROP TABLE IF EXISTS marts.dim_employer CASCADE;

CREATE TABLE marts.dim_employer (
    employer_key      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organisation_name_normalised text NOT NULL UNIQUE,
    display_name      text    NOT NULL,
    name_variant_count integer NOT NULL,

    CONSTRAINT ck_dim_employer_variants CHECK (name_variant_count >= 1)
);

INSERT INTO marts.dim_employer (organisation_name_normalised, display_name, name_variant_count)
WITH spellings AS (
    SELECT organisation_name_normalised,
           organisation_name,
           count(*) AS times_published
    FROM staging.stg_licensed_employers
    WHERE organisation_name_normalised IS NOT NULL
    GROUP BY organisation_name_normalised, organisation_name
),
ranked AS (
    SELECT *,
           -- DISTINCT ON keeps the first row per group, so the ORDER BY
           -- decides which spelling wins: most published first, then
           -- alphabetical as a deterministic tie-break. Without the tie-break
           -- the chosen name could differ between runs.
           count(*)      OVER (PARTITION BY organisation_name_normalised) AS variant_count
    FROM spellings
)
SELECT DISTINCT ON (organisation_name_normalised)
       organisation_name_normalised,
       organisation_name,
       variant_count
FROM ranked
ORDER BY organisation_name_normalised, times_published DESC, organisation_name;
