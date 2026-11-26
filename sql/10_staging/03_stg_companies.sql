-- Staging table for Companies House company data.
--
-- Built from raw.companies. Only the columns this project uses are carried
-- forward; the previous-name and mortgage columns stay in raw, where they can
-- always be fetched from if needed. Narrowing 55 columns to 17 makes every
-- later query on 5.7 million rows cheaper.
--
-- Cleaning decisions:
--
--   1. btrim, and blank strings become NULL.
--   2. Dates are DD/MM/YYYY in the file. PostgreSQL will not read that under
--      default settings, so they are converted explicitly. Anything not
--      matching the expected shape becomes NULL rather than aborting the
--      build; sql/60_quality counts how many that was.
--   3. SIC values arrive as "99999 - Dormant Company": one field holding a
--      code and a description. Split into two columns.
--   4. company_name_normalised is added, using the same function the register
--      side uses.

DROP TABLE IF EXISTS staging.stg_companies;

CREATE TABLE staging.stg_companies AS
WITH trimmed AS (
    SELECT
        nullif(btrim(company_number), '')            AS company_number,
        nullif(btrim(company_name), '')              AS company_name,
        nullif(btrim(company_category), '')          AS company_category,
        nullif(btrim(company_status), '')            AS company_status,
        nullif(btrim(country_of_origin), '')         AS country_of_origin,
        nullif(btrim(incorporation_date), '')        AS incorporation_date_text,
        nullif(btrim(dissolution_date), '')          AS dissolution_date_text,
        nullif(btrim(reg_address_post_town), '')     AS post_town,
        nullif(btrim(reg_address_county), '')        AS county,
        nullif(btrim(reg_address_country), '')       AS country,
        nullif(btrim(reg_address_post_code), '')     AS post_code,
        nullif(btrim(sic_code_sic_text_1), '')       AS sic_1,
        nullif(btrim(sic_code_sic_text_2), '')       AS sic_2,
        nullif(btrim(sic_code_sic_text_3), '')       AS sic_3,
        nullif(btrim(sic_code_sic_text_4), '')       AS sic_4,
        nullif(btrim(uri), '')                       AS uri,
        source_file
    FROM raw.companies
)
SELECT
    company_number,
    company_name,
    staging.normalise_org_name(company_name) AS company_name_normalised,
    company_category,
    company_status,
    country_of_origin,
    -- A date is converted only if it matches DD/MM/YYYY exactly. Checking the
    -- shape first means a stray value yields NULL instead of raising an error
    -- and destroying the whole 5.7 million row build.
    CASE WHEN incorporation_date_text ~ '^\d{2}/\d{2}/\d{4}$'
         THEN to_date(incorporation_date_text, 'DD/MM/YYYY') END AS incorporation_date,
    CASE WHEN dissolution_date_text ~ '^\d{2}/\d{2}/\d{4}$'
         THEN to_date(dissolution_date_text, 'DD/MM/YYYY') END  AS dissolution_date,
    -- Kept so the quality checks can count conversions that failed. A NULL
    -- date with a non-NULL original is a rejected value, not an absent one.
    incorporation_date_text,
    post_town,
    county,
    country,
    post_code,
    -- "99999 - Dormant Company" -> code "99999", description "Dormant Company".
    -- The separator is " - ", and descriptions themselves contain hyphens
    -- ("Non-specialised wholesale trade"), so the split is anchored to the
    -- digits at the start rather than splitting on every hyphen.
    substring(sic_1 from '^(\d+)')         AS sic_code_1,
    btrim(substring(sic_1 from '^\d+\s*-\s*(.*)$')) AS sic_description_1,
    substring(sic_2 from '^(\d+)')         AS sic_code_2,
    substring(sic_3 from '^(\d+)')         AS sic_code_3,
    substring(sic_4 from '^(\d+)')         AS sic_code_4,
    uri,
    source_file
FROM trimmed;

ALTER TABLE staging.stg_companies
    ALTER COLUMN company_number SET NOT NULL;

CREATE INDEX ix_stg_companies_normalised
    ON staging.stg_companies (company_name_normalised);

-- Trigram index for the fuzzy matching pass. It belongs here, not in the
-- matching layer, because this file DROPs and recreates the table and would
-- otherwise destroy it. Measured consequence of its absence: a single fuzzy
-- lookup takes 4.9 s instead of 51 ms, which turns the 27,251-lookup pass
-- from 19 minutes into roughly 37 hours.
SET maintenance_work_mem = '512MB';
CREATE INDEX ix_stg_companies_name_trgm
    ON staging.stg_companies USING gin (company_name_normalised gin_trgm_ops);

-- Fresh statistics, so the planner knows the new index exists and how
-- selective the columns are. Without this the first queries after a rebuild
-- can choose a sequential scan anyway.
ANALYZE staging.stg_companies;
