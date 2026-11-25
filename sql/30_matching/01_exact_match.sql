-- Exact matching: register employers to Companies House companies.
--
-- One row per distinct normalised employer name, recording the outcome
-- whatever it is. Names that could not be matched are kept with
-- match_method = 'none' rather than being left out, because a match table
-- that only contains successes cannot tell you the match rate.
--
-- Note on the data: the Free Company Data Product contains only companies
-- currently on the register. Statuses such as 'Liquidation' or
-- 'Active - Proposal to Strike off' appear, but genuinely dissolved companies
-- do not. Status is therefore recorded as an attribute and never used to
-- filter candidates - doing so would drop real matches for no reason.

DROP TABLE IF EXISTS marts.employer_company_match;

CREATE TABLE marts.employer_company_match (
    organisation_name_normalised text        PRIMARY KEY,
    company_number               text,
    match_method                 text        NOT NULL,
    similarity_score             numeric(4,3),
    candidate_count              integer     NOT NULL DEFAULT 0,
    matched_at                   timestamptz NOT NULL DEFAULT now(),

    -- Only these four outcomes are possible. A typo in a later INSERT fails
    -- loudly instead of creating a fifth category nobody notices.
    CONSTRAINT ck_match_method CHECK (
        match_method IN ('exact', 'fuzzy', 'ambiguous', 'none')
    ),
    -- A matched row must name a company; an unmatched row must not.
    CONSTRAINT ck_match_has_company CHECK (
        (match_method IN ('exact', 'fuzzy') AND company_number IS NOT NULL)
        OR
        (match_method IN ('ambiguous', 'none') AND company_number IS NULL)
    ),
    CONSTRAINT ck_similarity_range CHECK (
        similarity_score IS NULL OR (similarity_score >= 0 AND similarity_score <= 1)
    )
);

-- Every distinct employer name starts as unmatched. Later passes update rows.
INSERT INTO marts.employer_company_match (organisation_name_normalised, match_method)
SELECT DISTINCT organisation_name_normalised, 'none'
FROM staging.stg_licensed_employers
WHERE organisation_name_normalised IS NOT NULL;

-- Count how many companies share each normalised name. This is what decides
-- whether a name can be matched at all.
WITH candidates AS (
    SELECT c.company_name_normalised AS n,
           count(*)                  AS candidate_count,
           min(c.company_number)     AS only_company_number
    FROM staging.stg_companies c
    JOIN marts.employer_company_match m
      ON m.organisation_name_normalised = c.company_name_normalised
    GROUP BY c.company_name_normalised
)
UPDATE marts.employer_company_match m
SET candidate_count = candidates.candidate_count,
    -- Exactly one company with this name: a confident match.
    -- More than one: the name alone cannot say which, so no company is
    -- recorded. Guessing here would silently attach an employer to the wrong
    -- company and every downstream figure would inherit the error.
    company_number   = CASE WHEN candidates.candidate_count = 1
                            THEN candidates.only_company_number END,
    match_method     = CASE WHEN candidates.candidate_count = 1
                            THEN 'exact' ELSE 'ambiguous' END,
    similarity_score = CASE WHEN candidates.candidate_count = 1
                            THEN 1.000 END
FROM candidates
WHERE candidates.n = m.organisation_name_normalised;

CREATE INDEX ix_employer_company_match_method
    ON marts.employer_company_match (match_method);
CREATE INDEX ix_employer_company_match_company
    ON marts.employer_company_match (company_number);
