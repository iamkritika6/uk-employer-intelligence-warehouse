-- Two index experiments on staging.stg_companies (5,711,779 rows).
--
-- Both drop the index, measure, create it, and measure again, so the whole
-- thing is reproducible rather than a pair of numbers someone has to trust.
-- Running this takes a few minutes, mostly rebuilding the GIN index.
--
-- The second experiment is included BECAUSE it does not work. An index that
-- changes nothing is a more useful thing to understand than one that helps.

\timing on

\echo ''
\echo '================================================================'
\echo 'EXPERIMENT 1: trigram GIN index for fuzzy name matching'
\echo '================================================================'
\echo 'Query: find companies whose normalised name is similar to a given name.'
\echo 'This is the query the fuzzy matching pass runs 27,251 times.'
\echo ''

SET pg_trgm.similarity_threshold = 0.85;

DROP INDEX IF EXISTS staging.ix_stg_companies_name_trgm;

\echo '--- BEFORE (no trigram index) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT company_number, company_name_normalised,
       similarity(company_name_normalised, 'riverside medical centre') AS sim
FROM staging.stg_companies
WHERE company_name_normalised % 'riverside medical centre'
ORDER BY sim DESC
LIMIT 5;

SET maintenance_work_mem = '512MB';
CREATE INDEX ix_stg_companies_name_trgm
    ON staging.stg_companies USING gin (company_name_normalised gin_trgm_ops);
ANALYZE staging.stg_companies;

\echo '--- AFTER (trigram GIN index) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT company_number, company_name_normalised,
       similarity(company_name_normalised, 'riverside medical centre') AS sim
FROM staging.stg_companies
WHERE company_name_normalised % 'riverside medical centre'
ORDER BY sim DESC
LIMIT 5;


\echo ''
\echo '================================================================'
\echo 'EXPERIMENT 2: B-tree index on company_status'
\echo '================================================================'
\echo 'Query: count companies whose status is Active.'
\echo ''
\echo 'PREDICTION (recorded before running, and WRONG): no improvement.'
\echo '5,179,256 of 5,711,779 rows - 91% - are Active, and the usual rule is'
\echo 'that an index is ignored when a query touches most of the table.'
\echo ''
\echo 'WHAT ACTUALLY HAPPENED: 357 ms -> 169 ms, roughly twice as fast, using'
\echo 'a Parallel Index Only Scan. The rule above assumes the index is used to'
\echo 'find rows and then fetch them from the table. Here nothing from the'
\echo 'table is needed: the query only counts, and company_status is in the'
\echo 'index. PostgreSQL reads the 38 MB index and never touches the 2.7 GB'
\echo 'table at all. Low selectivity did not matter because the heap was'
\echo 'never visited.'
\echo ''

DROP INDEX IF EXISTS staging.ix_stg_companies_status;

\echo '--- BEFORE (no index on company_status) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM staging.stg_companies WHERE company_status = 'Active';

CREATE INDEX ix_stg_companies_status ON staging.stg_companies (company_status);
ANALYZE staging.stg_companies;

\echo '--- AFTER (index on company_status) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM staging.stg_companies WHERE company_status = 'Active';

\echo ''
\echo '--- The same index against a SELECTIVE value, for contrast ---'
\echo 'Only 182 companies have status RECEIVERSHIP.'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM staging.stg_companies WHERE company_status = 'RECEIVERSHIP';

\echo ''
\echo '--- index sizes ---'
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE relname = 'stg_companies'
ORDER BY pg_relation_size(indexrelid) DESC;
