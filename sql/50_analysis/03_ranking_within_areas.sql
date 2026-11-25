-- QUESTION: Within London, Berkshire and Reading specifically, which
--           technology employers' towns rank highest, and how does each area
--           compare?
--
-- Area is taken from the county Companies House publishes for the matched
-- company, because the register's own county field is blank in two thirds of
-- rows. Coverage is therefore limited to exactly-matched employers and is
-- reported alongside the counts rather than hidden.
--
-- Technique: PARTITION BY to rank within each area independently, so the top
-- town in Berkshire is not buried beneath London's volume.
--
-- IMPORTANT, because the result is easy to misread: Reading is in Berkshire,
-- so the three areas are not mutually exclusive. CASE stops at its first
-- matching branch, so a Reading company whose county reads "Berkshire" is
-- counted under Berkshire, and the "Reading" area holds only Reading
-- addresses whose county field says something else or is blank. That is why
-- READING appears twice with different figures. The alternative - making the
-- areas exclusive - would answer a different question from the one asked.

WITH area_employers AS (
    SELECT
        CASE
            WHEN upper(c.county) = 'BERKSHIRE'                      THEN 'Berkshire'
            WHEN upper(c.post_town) = 'READING'                     THEN 'Reading'
            WHEN upper(c.county) IN ('GREATER LONDON', 'LONDON')    THEN 'London'
        END                                 AS area,
        c.post_town                         AS town,
        f.employer_key
    FROM marts.fact_employer_snapshot f
    JOIN analysis.v_technology_company c ON c.company_key = f.company_key
),
counted AS (
    SELECT area, town, count(DISTINCT employer_key) AS tech_employers
    FROM area_employers
    WHERE area IS NOT NULL AND town IS NOT NULL
    GROUP BY area, town
)
SELECT
    area,
    DENSE_RANK() OVER (PARTITION BY area ORDER BY tech_employers DESC) AS rank_in_area,
    town,
    tech_employers,
    ROUND(100.0 * tech_employers
          / SUM(tech_employers) OVER (PARTITION BY area), 1)           AS pct_of_area
FROM counted
WHERE tech_employers >= 3
ORDER BY area, tech_employers DESC;
