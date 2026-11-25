-- QUESTION: Where are technology-sector registered employers located?
--
-- "Technology" is defined in 00_technology_sic_definition.sql and restricted
-- to exact name matches, so the SIC code genuinely belongs to this employer.
--
-- Technique: CTEs, a window function for rank, and conditional aggregation to
-- show what share of each town's employers are technology employers.

WITH tech_by_town AS (
    SELECT l.town,
           count(DISTINCT f.employer_key) FILTER (WHERE t.company_key IS NOT NULL) AS tech_employers,
           count(DISTINCT f.employer_key)                                          AS all_employers
    FROM marts.fact_employer_snapshot f
    JOIN marts.dim_location l        ON l.location_key = f.location_key
    LEFT JOIN analysis.v_technology_company t ON t.company_key = f.company_key
    WHERE NOT l.is_unknown
    GROUP BY l.town
)
SELECT
    RANK() OVER (ORDER BY tech_employers DESC) AS rank,
    town,
    tech_employers,
    all_employers,
    ROUND(100.0 * tech_employers / NULLIF(all_employers, 0), 1) AS pct_of_town
FROM tech_by_town
WHERE tech_employers > 0
ORDER BY tech_employers DESC
LIMIT 20;
