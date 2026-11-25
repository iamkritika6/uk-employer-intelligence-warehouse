-- QUESTION: What is the leading sector among registered employers in each of
--           the largest towns?
--
-- Technique: RANK inside a PARTITION BY town to pick the top sector per town,
-- which is the standard "top N per group" shape - the thing a self-join and a
-- MAX subquery do badly.
--
-- Uses the SIC description rather than the code, since the question is about
-- what the sector is, not its number.

WITH town_sector AS (
    SELECT l.town,
           c.sic_description_1 AS sector,
           count(DISTINCT f.employer_key) AS employers
    FROM marts.fact_employer_snapshot f
    JOIN marts.dim_location l ON l.location_key = f.location_key
    JOIN marts.dim_company  c ON c.company_key  = f.company_key
    WHERE NOT l.is_unknown
      AND c.match_method = 'exact'
      AND c.sic_description_1 IS NOT NULL
    GROUP BY l.town, c.sic_description_1
),
town_totals AS (
    SELECT town, SUM(employers) AS town_employers
    FROM town_sector GROUP BY town
),
ranked AS (
    SELECT ts.town, ts.sector, ts.employers, tt.town_employers,
           RANK() OVER (PARTITION BY ts.town ORDER BY ts.employers DESC) AS rnk
    FROM town_sector ts
    JOIN town_totals tt ON tt.town = ts.town
    WHERE tt.town_employers >= 200     -- larger towns only; below this a
                                       -- "leading sector" is one or two firms
)
SELECT town, town_employers, sector, employers,
       ROUND(100.0 * employers / town_employers, 1) AS pct_of_town
FROM ranked
WHERE rnk = 1
ORDER BY town_employers DESC
LIMIT 20;
