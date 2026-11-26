-- QUESTION: How are employer ratings distributed across employer types,
--           and are B ratings concentrated anywhere?
--
-- Technique: conditional aggregation (COUNT with FILTER) to turn rows into
-- columns, which is how a breakdown like this is produced without writing one
-- query per rating.
--
-- Counts licences (rows), not organisations: the same employer can hold
-- different ratings on different routes, and collapsing that would hide it.

SELECT
    employer_type,
    count(*)                                            AS licences,
    count(*) FILTER (WHERE rating = 'A')                AS rating_a,
    count(*) FILTER (WHERE rating = 'B')                AS rating_b,
    count(*) FILTER (WHERE rating LIKE 'A (%')          AS rating_a_variant,
    count(*) FILTER (WHERE rating NOT IN ('A','B')
                       AND rating NOT LIKE 'A (%')      AS rating_other,
    count(*) FILTER (WHERE rating IS NULL)              AS rating_missing,
    ROUND(100.0 * count(*) FILTER (WHERE rating = 'B') / count(*), 3) AS pct_rating_b
FROM marts.fact_employer_snapshot
GROUP BY employer_type
ORDER BY licences DESC;
