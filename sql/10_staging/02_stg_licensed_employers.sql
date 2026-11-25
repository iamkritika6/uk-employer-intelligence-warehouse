-- Staging table for the licensed employer register.
--
-- Built from raw.licensed_employers. Rebuilt in full each run (DROP then
-- CREATE), because staging holds no information of its own: everything in it
-- is derived from raw, so it can always be thrown away and remade.
--
-- Cleaning decisions, each measured in sql/60_quality:
--
--   1. btrim every text value. The file has a space after every comma, so
--      " London  " and "London" arrive as different towns.
--   2. Blank strings become NULL. "" and "no value" mean the same thing here
--      and keeping both forces every later query to check for both.
--   3. "Type & Rating" is split into employer_type and rating.
--   4. organisation_name_normalised is added for matching.

DROP TABLE IF EXISTS staging.stg_licensed_employers;

CREATE TABLE staging.stg_licensed_employers AS
WITH trimmed AS (
    -- Step 1 and 2 together: trim, then turn the empty results into NULL.
    SELECT
        nullif(btrim(organisation_name), '') AS organisation_name,
        nullif(btrim(town_city), '')         AS town,
        nullif(btrim(county), '')            AS county,
        nullif(btrim(type_and_rating), '')   AS type_and_rating,
        nullif(btrim(route), '')             AS route,
        source_file
    FROM raw.licensed_employers
),
split AS (
    SELECT
        *,
        -- Step 3. The column looks like "Worker (A rating)": a type, then a
        -- bracketed rating. Two capture groups:
        --   (.*?)   the type, non-greedy so it stops at the FIRST " ("
        --   (.*)    everything inside the brackets, greedy so that the nested
        --           brackets in "Worker (A (Premium))" survive intact
        substring(type_and_rating from '^(.*?)\s*\(')        AS employer_type_extracted,
        substring(type_and_rating from '\((.*)\)\s*$')       AS rating_extracted
    FROM trimmed
)
SELECT
    organisation_name,
    staging.normalise_org_name(organisation_name) AS organisation_name_normalised,
    town,
    county,
    -- If the value had no brackets at all, both captures are NULL. Fall back
    -- to the whole string rather than losing the row's meaning silently.
    coalesce(btrim(employer_type_extracted), type_and_rating) AS employer_type,
    -- Most ratings read "A rating" or "B rating"; the trailing word carries no
    -- information, so it is removed. Values that do not follow that pattern,
    -- such as "A (Premium)" or "UK Expansion Worker: Provisional", are kept
    -- exactly as published rather than forced into an A/B shape they do not
    -- have.
    nullif(btrim(regexp_replace(btrim(rating_extracted), '\s+rating$', '')), '') AS rating,
    type_and_rating AS type_and_rating_original,
    route,
    source_file
FROM split;

-- Constraints are added after the fact because CREATE TABLE AS cannot declare
-- them. A row with no organisation name is meaningless here, and the load
-- should fail loudly if one ever appears rather than carrying it forward.
ALTER TABLE staging.stg_licensed_employers
    ALTER COLUMN organisation_name SET NOT NULL;

CREATE INDEX ix_stg_licensed_employers_normalised
    ON staging.stg_licensed_employers (organisation_name_normalised);
