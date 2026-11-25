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

CREATE TABLE marts.dim_location (
    location_key  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    town          text,
    county        text,
    is_unknown    boolean NOT NULL DEFAULT false,

    -- A real location must name a town; only the unknown member may not.
    CONSTRAINT ck_dim_location_town CHECK (
        (is_unknown AND town IS NULL) OR (NOT is_unknown AND town IS NOT NULL)
    )
);

-- The unknown member first, so it exists before any fact row needs it.
INSERT INTO marts.dim_location (town, county, is_unknown)
VALUES (NULL, NULL, true);

INSERT INTO marts.dim_location (town, county)
SELECT DISTINCT town, county
FROM staging.stg_licensed_employers
WHERE town IS NOT NULL;

-- Two towns of the same name in different counties are different places, so
-- the pair is unique, not the town alone. NULLS NOT DISTINCT makes two rows
-- with the same town and both counties NULL count as duplicates, which is the
-- behaviour wanted here - without it, PostgreSQL treats NULLs as distinct and
-- the constraint would allow repeats.
CREATE UNIQUE INDEX uq_dim_location_town_county
    ON marts.dim_location (town, county) NULLS NOT DISTINCT
    WHERE NOT is_unknown;
