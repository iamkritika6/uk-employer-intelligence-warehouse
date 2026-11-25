-- Fuzzy matching for the names that exact matching could not place.
--
-- Only rows left as match_method = 'none' are considered. Exact matches are
-- never revisited, and 'ambiguous' rows stay ambiguous: if two companies share
-- a name exactly, similarity cannot separate them either.
--
-- Method: pg_trgm trigram similarity. A string is cut into three-character
-- sequences and two strings are scored by how many they share, from 0 to 1.
-- "acme ltd" and "acme limited" score 0.375 - low, which is why names are
-- normalised first and fuzzy matching only handles what is left.
--
-- Threshold: candidates are collected at 0.80 and the score of every match is
-- stored. The threshold actually used for analysis is applied later and can be
-- revised without re-running this, because the scores are kept. Picking a
-- number first and reporting only what survives it hides the evidence for the
-- choice.
--
-- The GIN trigram index is what makes this possible at all. Measured on this
-- machine, one lookup takes 4,909 ms without it and 51 ms with it: the
-- difference between roughly 37 hours and under half an hour for 27,251 names.

SET pg_trgm.similarity_threshold = 0.80;

WITH unmatched AS (
    SELECT organisation_name_normalised AS n
    FROM marts.employer_company_match
    WHERE match_method = 'none'
),
best AS (
    -- LATERAL runs the inner query once per unmatched name, which is what
    -- lets each row use its own value in the inner WHERE clause.
    SELECT u.n, b.company_number, b.sim, b.tied_candidates
    FROM unmatched u
    CROSS JOIN LATERAL (
        SELECT c.company_number,
               similarity(c.company_name_normalised, u.n) AS sim,
               count(*) OVER () AS tied_candidates
        FROM staging.stg_companies c
        WHERE c.company_name_normalised % u.n
        ORDER BY similarity(c.company_name_normalised, u.n) DESC,
                 c.company_number          -- deterministic tie-break
        LIMIT 1
    ) b
)
UPDATE marts.employer_company_match m
SET company_number   = best.company_number,
    match_method     = 'fuzzy',
    similarity_score = round(best.sim::numeric, 3),
    candidate_count  = best.tied_candidates
FROM best
WHERE best.n = m.organisation_name_normalised
  AND m.match_method = 'none';
