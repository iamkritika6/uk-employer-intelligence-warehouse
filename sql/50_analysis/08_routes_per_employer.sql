-- QUESTION: How many routes is a typical employer licensed on, and which
--           employers hold the widest range?
--
-- Technique: aggregation to a count per employer, then DENSE_RANK over that
-- count. DENSE_RANK rather than RANK so that the many employers tied on the
-- same number of routes produce consecutive rank numbers.
--
-- The rank cut-off is 2, not 3. At 3 the query returned 163 rows, because
-- ranking by a value with only six possible levels means the third level
-- (4 routes) contains over a hundred tied employers. A worked reminder that
-- "top 3 ranks" and "top 3 rows" are different things when ties are common.

WITH per_employer AS (
    SELECT f.employer_key,
           e.display_name,
           count(DISTINCT f.route) AS routes
    FROM marts.fact_employer_snapshot f
    JOIN marts.dim_employer e ON e.employer_key = f.employer_key
    GROUP BY f.employer_key, e.display_name
),
distribution AS (
    SELECT routes, count(*) AS employers
    FROM per_employer
    GROUP BY routes
)
SELECT
    'distribution'                                     AS section,
    routes::text                                       AS detail,
    employers,
    ROUND(100.0 * employers / SUM(employers) OVER (), 2) AS pct
FROM distribution

UNION ALL

SELECT
    'widest range',
    display_name,
    routes,
    NULL
FROM (
    SELECT display_name, routes,
           DENSE_RANK() OVER (ORDER BY routes DESC) AS rnk
    FROM per_employer
) ranked
WHERE rnk <= 2
ORDER BY section, employers DESC, detail;
