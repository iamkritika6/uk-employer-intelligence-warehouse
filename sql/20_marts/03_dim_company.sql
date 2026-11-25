-- dim_company: Companies House attributes for the companies that matching
-- actually linked to an employer.
--
-- Grain: one row per company number.
--
-- Only matched companies are carried into the mart. Loading all 5,711,779
-- would make the dimension 56 times larger than anything the facts reference,
-- for no analytical gain. The full set stays in staging.stg_companies, which
-- is where the performance work runs; nothing is lost.
--
-- match_method and similarity_score are deliberately carried onto this row.
-- Any query reading company attributes can therefore see, without a further
-- join, whether the link it is relying on was exact or fuzzy - and fuzzy links
-- are known to be wrong at least 21% of the time (docs/match_sample_check.md).

DROP TABLE IF EXISTS marts.dim_company CASCADE;

CREATE TABLE marts.dim_company (
    company_key        integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_number     text    NOT NULL UNIQUE,
    company_name       text,
    company_category   text,
    company_status     text,
    incorporation_date date,
    post_town          text,
    county             text,
    post_code          text,
    sic_code_1         text,
    sic_description_1  text,
    sic_code_2         text,
    sic_code_3         text,
    sic_code_4         text,
    match_method       text    NOT NULL,
    similarity_score   numeric(4,3),

    CONSTRAINT ck_dim_company_method CHECK (match_method IN ('exact', 'fuzzy')),
    -- Companies House was founded in 1844; a date before that, or in the
    -- future, is a data error rather than a very old company.
    CONSTRAINT ck_dim_company_incorporation CHECK (
        incorporation_date IS NULL
        OR (incorporation_date >= DATE '1844-01-01'
            AND incorporation_date <= CURRENT_DATE)
    )
);

INSERT INTO marts.dim_company (
    company_number, company_name, company_category, company_status,
    incorporation_date, post_town, county, post_code,
    sic_code_1, sic_description_1, sic_code_2, sic_code_3, sic_code_4,
    match_method, similarity_score
)
SELECT c.company_number, c.company_name, c.company_category, c.company_status,
       c.incorporation_date, c.post_town, c.county, c.post_code,
       c.sic_code_1, c.sic_description_1, c.sic_code_2, c.sic_code_3, c.sic_code_4,
       m.match_method, m.similarity_score
FROM staging.stg_companies c
JOIN (
    -- One employer name maps to one company, but several employer names can
    -- map to the same company (different spellings that normalised apart).
    -- Collapse to one row per company, preferring an exact link over a fuzzy
    -- one if both exist.
    SELECT DISTINCT ON (company_number)
           company_number, match_method, similarity_score
    FROM marts.employer_company_match
    WHERE company_number IS NOT NULL
    ORDER BY company_number,
             CASE match_method WHEN 'exact' THEN 0 ELSE 1 END,
             similarity_score DESC NULLS LAST
) m ON m.company_number = c.company_number;

CREATE INDEX ix_dim_company_sic1  ON marts.dim_company (sic_code_1);
CREATE INDEX ix_dim_company_town  ON marts.dim_company (post_town);
