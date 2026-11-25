-- QUESTION: How old are the companies behind registered employers? Is the
--           register dominated by long-established firms or recent ones?
--
-- Technique: CASE segmentation into age bands, with a window function for
-- each band's share.
--
-- Exact matches only. An incorporation date taken from a wrongly matched
-- company is worse than no date at all, because it looks like evidence.

WITH aged AS (
    SELECT DISTINCT
        f.employer_key,
        c.incorporation_date,
        -- AGE returns an interval; EXTRACT pulls the whole years out of it.
        EXTRACT(YEAR FROM age(CURRENT_DATE, c.incorporation_date))::int AS years_old
    FROM marts.fact_employer_snapshot f
    JOIN marts.dim_company c ON c.company_key = f.company_key
    WHERE c.match_method = 'exact'
      AND c.incorporation_date IS NOT NULL
),
banded AS (
    SELECT
        CASE
            WHEN years_old < 2  THEN '0-1 years'
            WHEN years_old < 5  THEN '2-4 years'
            WHEN years_old < 10 THEN '5-9 years'
            WHEN years_old < 20 THEN '10-19 years'
            WHEN years_old < 50 THEN '20-49 years'
            ELSE '50+ years'
        END AS age_band,
        -- Sort key, so the bands come out in age order rather than
        -- alphabetically ("10-19 years" would otherwise precede "2-4 years").
        CASE
            WHEN years_old < 2  THEN 1
            WHEN years_old < 5  THEN 2
            WHEN years_old < 10 THEN 3
            WHEN years_old < 20 THEN 4
            WHEN years_old < 50 THEN 5
            ELSE 6
        END AS band_order,
        employer_key
    FROM aged
)
SELECT
    age_band,
    count(*)                                                      AS employers,
    ROUND(100.0 * count(*) / SUM(count(*)) OVER (), 2)            AS pct,
    ROUND(100.0 * SUM(count(*)) OVER (ORDER BY band_order
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          / SUM(count(*)) OVER (), 2)                             AS cumulative_pct
FROM banded
GROUP BY age_band, band_order
ORDER BY band_order;
