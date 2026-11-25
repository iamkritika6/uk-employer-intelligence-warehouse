-- QUESTION: How concentrated is the register? Does a small number of towns
--           account for most registered employers?
--
-- Technique: NTILE to split towns into ten equal-sized groups by size, plus a
-- running total to express the classic concentration question - what share of
-- employers sit in the top tenth of towns.

WITH by_town AS (
    SELECT l.town, count(DISTINCT f.employer_key) AS employers
    FROM marts.fact_employer_snapshot f
    JOIN marts.dim_location l ON l.location_key = f.location_key
    WHERE NOT l.is_unknown
    GROUP BY l.town
),
bucketed AS (
    SELECT town, employers,
           NTILE(10) OVER (ORDER BY employers DESC) AS decile
    FROM by_town
)
SELECT
    decile,
    count(*)                                              AS towns,
    SUM(employers)                                        AS employers,
    ROUND(100.0 * SUM(employers) / SUM(SUM(employers)) OVER (), 2) AS pct_of_employers,
    MIN(employers)                                        AS smallest_town,
    MAX(employers)                                        AS largest_town
FROM bucketed
GROUP BY decile
ORDER BY decile;
