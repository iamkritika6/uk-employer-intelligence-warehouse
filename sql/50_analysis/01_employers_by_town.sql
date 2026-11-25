-- QUESTION: Which towns have the most registered employers, and how
--           concentrated is the register geographically?
--
-- Technique: RANK for position, a window SUM for share of total, and a running
-- total ordered by size to show concentration.
--
-- Counts DISTINCT employer_key, not rows. A row is a licence (employer x
-- route); an organisation licensed on three routes would otherwise be counted
-- three times.

WITH by_town AS (
    SELECT l.town,
           count(DISTINCT f.employer_key) AS employers
    FROM marts.fact_employer_snapshot f
    JOIN marts.dim_location l ON l.location_key = f.location_key
    WHERE NOT l.is_unknown
    GROUP BY l.town
)
SELECT
    RANK() OVER (ORDER BY employers DESC)                        AS rank,
    town,
    employers,
    ROUND(100.0 * employers / SUM(employers) OVER (), 2)         AS pct_of_total,
    -- Running total of the share, largest town first: how much of the whole
    -- register the top N towns account for.
    ROUND(100.0 * SUM(employers) OVER (ORDER BY employers DESC
                                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / SUM(employers) OVER (), 2)                           AS cumulative_pct
FROM by_town
ORDER BY employers DESC
LIMIT 20;
