-- Data quality checks. Every check prints PASS or FAIL with the numbers
-- behind it, so a failure says what is wrong rather than only that something
-- is.
--
-- Checks are written as one UNION ALL over a common shape
-- (check_name, expected, actual, status) so that adding a check means adding
-- a SELECT, and the whole set can be read at a glance.
--
-- Some checks duplicate a database constraint - orphan foreign keys, for
-- instance, cannot exist while the constraint does. They are kept anyway:
-- constraints can be dropped during a load and not restored, and a check that
-- can never fail still documents what is being relied on.
--
-- INFO rows are not failures. They report counts that are expected to be
-- non-zero and need watching rather than fixing.

WITH checks AS (

-- 1. Raw to staging: no rows lost in the register
SELECT 'register: raw rows = staging rows' AS check_name,
       (SELECT count(*) FROM raw.licensed_employers)::text      AS expected,
       (SELECT count(*) FROM staging.stg_licensed_employers)::text AS actual

UNION ALL
-- 2. Raw to staging: no rows lost in the company data
SELECT 'companies: raw rows = staging rows',
       (SELECT count(*) FROM raw.companies)::text,
       (SELECT count(*) FROM staging.stg_companies)::text

UNION ALL
-- 3. Staging to fact: every published row is represented. The fact table is
--    deduplicated to its grain, so the comparison is against the sum of
--    source_row_count, not the row count.
SELECT 'fact: source rows represented = staging rows',
       (SELECT count(*) FROM staging.stg_licensed_employers)::text,
       (SELECT coalesce(sum(source_row_count),0) FROM marts.fact_employer_snapshot)::text

UNION ALL
-- 4. No employer row without a name
SELECT 'staging: organisation_name never null',
       '0',
       (SELECT count(*) FROM staging.stg_licensed_employers WHERE organisation_name IS NULL)::text

UNION ALL
-- 5. Normalisation never produces an empty string (it must be NULL or real)
SELECT 'staging: normalised name never empty string',
       '0',
       (SELECT count(*) FROM staging.stg_licensed_employers WHERE organisation_name_normalised = '')::text

UNION ALL
-- 6. Every date that had a value converted successfully
SELECT 'companies: no rejected incorporation dates',
       '0',
       (SELECT count(*) FROM staging.stg_companies
        WHERE incorporation_date_text IS NOT NULL AND incorporation_date IS NULL)::text

UNION ALL
-- 7-9. Referential integrity: no fact row points at a missing dimension row
SELECT 'fact: no orphan employer_key',
       '0',
       (SELECT count(*) FROM marts.fact_employer_snapshot f
        LEFT JOIN marts.dim_employer d ON d.employer_key = f.employer_key
        WHERE d.employer_key IS NULL)::text

UNION ALL
SELECT 'fact: no orphan location_key',
       '0',
       (SELECT count(*) FROM marts.fact_employer_snapshot f
        LEFT JOIN marts.dim_location d ON d.location_key = f.location_key
        WHERE d.location_key IS NULL)::text

UNION ALL
SELECT 'fact: no orphan company_key',
       '0',
       (SELECT count(*) FROM marts.fact_employer_snapshot f
        LEFT JOIN marts.dim_company d ON d.company_key = f.company_key
        WHERE f.company_key IS NOT NULL AND d.company_key IS NULL)::text

UNION ALL
-- 10. The declared grain holds: no duplicates on the key
SELECT 'fact: grain is unique (employer, route, location, snapshot)',
       '0',
       (SELECT count(*) FROM (
            SELECT 1 FROM marts.fact_employer_snapshot
            GROUP BY employer_key, route, location_key, snapshot_date
            HAVING count(*) > 1) d)::text

UNION ALL
-- 11. Dimension keys are unique
SELECT 'dim_employer: normalised name is unique',
       (SELECT count(*) FROM marts.dim_employer)::text,
       (SELECT count(DISTINCT organisation_name_normalised) FROM marts.dim_employer)::text

UNION ALL
SELECT 'dim_company: company_number is unique',
       (SELECT count(*) FROM marts.dim_company)::text,
       (SELECT count(DISTINCT company_number) FROM marts.dim_company)::text

UNION ALL
-- 12. The match table agrees with itself: matched rows name a company,
--     unmatched rows do not
SELECT 'match: method and company_number agree',
       '0',
       (SELECT count(*) FROM marts.employer_company_match
        WHERE (match_method IN ('exact','fuzzy') AND company_number IS NULL)
           OR (match_method IN ('none','ambiguous') AND company_number IS NOT NULL))::text

UNION ALL
-- 13. No fuzzy match slipped in below the stated threshold
SELECT 'match: no fuzzy score below 0.80',
       '0',
       (SELECT count(*) FROM marts.employer_company_match
        WHERE match_method = 'fuzzy' AND similarity_score < 0.80)::text

UNION ALL
-- 14. Every employer name in the register appears in the match table
SELECT 'match: covers every distinct employer name',
       (SELECT count(DISTINCT organisation_name_normalised)
        FROM staging.stg_licensed_employers WHERE organisation_name_normalised IS NOT NULL)::text,
       (SELECT count(*) FROM marts.employer_company_match)::text

UNION ALL
-- 15. Towns are case-folded consistently: the bug that made London and LONDON
--     two towns must not come back
SELECT 'dim_location: no two rows differ only by case',
       (SELECT count(*) FROM marts.dim_location WHERE NOT is_unknown)::text,
       (SELECT count(DISTINCT (upper(town), upper(coalesce(county,''))))
        FROM marts.dim_location WHERE NOT is_unknown)::text

UNION ALL
-- 16. Exactly one unknown location member
SELECT 'dim_location: exactly one unknown member',
       '1',
       (SELECT count(*) FROM marts.dim_location WHERE is_unknown)::text

UNION ALL
-- 17. Incorporation dates are plausible
SELECT 'dim_company: no impossible incorporation dates',
       '0',
       (SELECT count(*) FROM marts.dim_company
        WHERE incorporation_date IS NOT NULL
          AND (incorporation_date < DATE '1844-01-01' OR incorporation_date > CURRENT_DATE))::text
)
SELECT check_name,
       expected,
       actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks

UNION ALL

-- Informational counts. These are expected to be non-zero; they are reported
-- so that a change in them is visible, not because anything is wrong.
SELECT 'INFO: fact rows collapsed from duplicate source rows',
       '', (SELECT count(*) FROM marts.fact_employer_snapshot WHERE source_row_count > 1)::text, 'INFO'
UNION ALL
SELECT 'INFO: fact rows with conflicting published ratings',
       '', (SELECT count(*) FROM marts.fact_employer_snapshot WHERE has_rating_conflict)::text, 'INFO'
UNION ALL
SELECT 'INFO: employer names with no Companies House match',
       '', (SELECT count(*) FROM marts.employer_company_match WHERE match_method = 'none')::text, 'INFO'
UNION ALL
SELECT 'INFO: employer names matched fuzzily (small sample suggests >=21% wrong)',
       '', (SELECT count(*) FROM marts.employer_company_match WHERE match_method = 'fuzzy')::text, 'INFO'
UNION ALL
SELECT 'INFO: companies with no SIC code (published as None Supplied)',
       '', (SELECT count(*) FROM staging.stg_companies WHERE sic_code_1 IS NULL)::text, 'INFO'
ORDER BY status, check_name;

