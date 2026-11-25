-- QUESTION: In which years were the companies behind registered employers
--           incorporated, and how did each year compare with the one before?
--
-- Technique: LAG to reach the previous row's value, which is how a
-- year-on-year change is computed without a self-join.
--
-- Note on reading this: it shows the incorporation years of companies that
-- are on the register TODAY. It is not a history of the register, and it is
-- not a survival curve - companies incorporated long ago that have since
-- closed are simply absent. Last 20 years only, because earlier years are
-- thin and the comparison becomes noise.

WITH per_year AS (
    SELECT
        EXTRACT(YEAR FROM c.incorporation_date)::int AS incorporation_year,
        count(DISTINCT f.employer_key)               AS employers
    FROM marts.fact_employer_snapshot f
    JOIN marts.dim_company c ON c.company_key = f.company_key
    WHERE c.match_method = 'exact'
      AND c.incorporation_date IS NOT NULL
      AND c.incorporation_date >= CURRENT_DATE - INTERVAL '20 years'
    GROUP BY 1
)
SELECT
    incorporation_year,
    employers,
    LAG(employers) OVER (ORDER BY incorporation_year)              AS previous_year,
    employers - LAG(employers) OVER (ORDER BY incorporation_year)  AS change,
    ROUND(100.0 * (employers - LAG(employers) OVER (ORDER BY incorporation_year))
          / NULLIF(LAG(employers) OVER (ORDER BY incorporation_year), 0), 1) AS pct_change
FROM per_year
ORDER BY incorporation_year;
