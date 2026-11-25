-- dim_location: one row per place an employer is published under.
--
-- Grain: one row per distinct (town, county) pair as published in the
-- register, plus one "unknown" member.
--
-- The unknown member (employer_key -1 style, here location_key for the row
-- where town IS NULL) exists because one register row has no town at all. The
-- alternative is a NULL foreign key in the fact table, which forces every
-- later query to use an outer join and makes counts quietly inconsistent
-- depending on whether the author remembered. A dimension row meaning
-- "not stated" keeps every fact row joinable.
--
-- County is NOT used as the main geography. It is blank in 95,020 of 143,220
-- register rows - two thirds - so any grouping by county would describe the
-- third that happens to be filled in. Town is published for all but one row.
--
-- No region column is derived here. The register publishes no region, and
-- inventing one from town names would be guesswork presented as data. Where
-- region-level analysis is needed later, it uses the county published by
-- Companies House for matched employers, with its coverage stated.

DROP TABLE IF EXISTS marts.dim_location CASCADE;

-- Case matters here and nearly produced wrong answers. The register publishes
-- "London", "LONDON", "london" and "lONDON" - four spellings of one city. The
-- first version of this dimension keyed on the published spelling, and London
-- appeared twice in the top two rows of every ranking. The dimension is now
-- keyed on the case-folded value, with the most frequently published spelling
-- kept for display.

CREATE TABLE marts.dim_location (
    location_key  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    town_key      text,           -- case-folded; the real identity of the place
    county_key    text,
    town          text,           -- most frequently published spelling
    county        text,
    spelling_count integer NOT NULL DEFAULT 1,
    is_unknown    boolean NOT NULL DEFAULT false,

    -- A real location must name a town; only the unknown member may not.
    CONSTRAINT ck_dim_location_town CHECK (
        (is_unknown AND town_key IS NULL) OR (NOT is_unknown AND town_key IS NOT NULL)
    )
);

-- The unknown member first, so it exists before any fact row needs it.
INSERT INTO marts.dim_location (town_key, county_key, town, county, is_unknown)
VALUES (NULL, NULL, NULL, NULL, true);

INSERT INTO marts.dim_location (town_key, county_key, town, county, spelling_count)
WITH spellings AS (
    SELECT town_key, county_key, town, county, count(*) AS times_published
    FROM staging.stg_licensed_employers
    WHERE town_key IS NOT NULL
    GROUP BY town_key, county_key, town, county
)
SELECT DISTINCT ON (town_key, county_key)
       town_key, county_key, town, county,
       count(*) OVER (PARTITION BY town_key, county_key) AS spelling_count
FROM spellings
-- Most published spelling wins; alphabetical tie-break keeps it deterministic.
ORDER BY town_key, county_key, times_published DESC, town;

-- Two towns of the same name in different counties are different places, so
-- the pair is unique, not the town alone. NULLS NOT DISTINCT makes two rows
-- with the same town and both counties NULL count as duplicates, which is the
-- behaviour wanted here - without it, PostgreSQL treats NULLs as distinct and
-- the constraint would allow repeats.
CREATE UNIQUE INDEX uq_dim_location_town_county
    ON marts.dim_location (town_key, county_key) NULLS NOT DISTINCT
    WHERE NOT is_unknown;
