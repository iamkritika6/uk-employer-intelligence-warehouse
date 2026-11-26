-- Test for the SCD Type 2 snapshot logic.
--
-- WHY A FIXTURE: only one real snapshot of the register has been loaded
-- (2026-10-15), so there is no real history to test against. Rather than
-- invent history in the warehouse - which would put fabricated rows next to
-- real ones - this builds four made-up employers in a separate `test` schema
-- and runs the real production function against them.
--
-- The data below is FICTIONAL. The schema is dropped and recreated each run.
--
-- The scenario covers the four things SCD2 has to get right:
--
--   Employer A  present in both snapshots, unchanged   -> 1 version, stays open
--   Employer B  rating changes A -> B                  -> 2 versions
--   Employer C  disappears from the second snapshot    -> 1 version, closed
--   Employer D  appears only in the second snapshot    -> 1 version, opened late

DROP SCHEMA IF EXISTS test CASCADE;
CREATE SCHEMA test;

-- Minimal copies of the structures the function needs.
CREATE TABLE test.dim_employer (
    employer_key integer PRIMARY KEY,
    display_name text NOT NULL
);

CREATE TABLE test.dim_location (
    location_key integer PRIMARY KEY,
    town         text
);

CREATE TABLE test.fact_employer_snapshot (
    employer_key  integer NOT NULL REFERENCES test.dim_employer (employer_key),
    location_key  integer NOT NULL REFERENCES test.dim_location (location_key),
    employer_type text    NOT NULL,
    rating        text,
    route         text    NOT NULL,
    snapshot_date date    NOT NULL
);

CREATE TABLE test.employer_history (
    employer_history_key bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employer_key  integer NOT NULL REFERENCES test.dim_employer (employer_key),
    route         text    NOT NULL,
    location_key  integer NOT NULL REFERENCES test.dim_location (location_key),
    employer_type text    NOT NULL,
    rating        text,
    valid_from    date    NOT NULL,
    valid_to      date    NOT NULL DEFAULT DATE '9999-12-31',
    is_current    boolean NOT NULL DEFAULT true,
    CONSTRAINT ck_history_dates CHECK (valid_to >= valid_from),
    CONSTRAINT ck_history_current CHECK (
        (is_current AND valid_to = DATE '9999-12-31')
        OR (NOT is_current AND valid_to < DATE '9999-12-31')
    )
);

CREATE UNIQUE INDEX uq_test_history_current
    ON test.employer_history (employer_key, route, location_key) WHERE is_current;

-- ---------------------------------------------------------------- fixture
INSERT INTO test.dim_employer VALUES
    (1, 'FIXTURE Employer A'),
    (2, 'FIXTURE Employer B'),
    (3, 'FIXTURE Employer C'),
    (4, 'FIXTURE Employer D');

INSERT INTO test.dim_location VALUES (10, 'FIXTURE TOWN');

-- Snapshot 1: A, B, C
INSERT INTO test.fact_employer_snapshot VALUES
    (1, 10, 'Worker', 'A', 'Skilled Worker', DATE '2026-01-01'),
    (2, 10, 'Worker', 'A', 'Skilled Worker', DATE '2026-01-01'),
    (3, 10, 'Worker', 'A', 'Skilled Worker', DATE '2026-01-01');

-- Snapshot 2: A unchanged, B downgraded to B, C gone, D new
INSERT INTO test.fact_employer_snapshot VALUES
    (1, 10, 'Worker', 'A', 'Skilled Worker', DATE '2026-02-01'),
    (2, 10, 'Worker', 'B', 'Skilled Worker', DATE '2026-02-01'),
    (4, 10, 'Worker', 'A', 'Skilled Worker', DATE '2026-02-01');

-- ---------------------------------------------------------------- run
\echo ''
\echo '--- applying snapshot 1 (expect 0 closed, 3 opened) ---'
SELECT * FROM marts.apply_employer_snapshot('test', DATE '2026-01-01');

\echo '--- applying snapshot 2 (expect 2 closed, 2 opened) ---'
SELECT * FROM marts.apply_employer_snapshot('test', DATE '2026-02-01');

\echo '--- applying snapshot 2 AGAIN (expect 0 closed, 0 opened: idempotent) ---'
SELECT * FROM marts.apply_employer_snapshot('test', DATE '2026-02-01');

\echo ''
\echo '--- resulting history ---'
SELECT e.display_name, h.rating, h.valid_from, h.valid_to, h.is_current
FROM test.employer_history h
JOIN test.dim_employer e ON e.employer_key = h.employer_key
ORDER BY e.display_name, h.valid_from;

-- ---------------------------------------------------------------- assertions
\echo ''
\echo '--- assertions ---'
WITH h AS (SELECT * FROM test.employer_history)
SELECT check_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
    SELECT 'total versions created' AS check_name, 5 AS expected,
           (SELECT count(*) FROM h)::int AS actual
    UNION ALL
    SELECT 'currently open versions', 3,
           (SELECT count(*) FROM h WHERE is_current)::int
    UNION ALL
    SELECT 'A: unchanged, one open version from snapshot 1', 1,
           (SELECT count(*) FROM h WHERE employer_key = 1
             AND is_current AND valid_from = DATE '2026-01-01')::int
    UNION ALL
    SELECT 'B: two versions after rating change', 2,
           (SELECT count(*) FROM h WHERE employer_key = 2)::int
    UNION ALL
    SELECT 'B: old version closed on snapshot 2 date', 1,
           (SELECT count(*) FROM h WHERE employer_key = 2
             AND rating = 'A' AND NOT is_current AND valid_to = DATE '2026-02-01')::int
    UNION ALL
    SELECT 'B: new version open with rating B', 1,
           (SELECT count(*) FROM h WHERE employer_key = 2
             AND rating = 'B' AND is_current AND valid_from = DATE '2026-02-01')::int
    UNION ALL
    SELECT 'C: removed, closed, no open version', 0,
           (SELECT count(*) FROM h WHERE employer_key = 3 AND is_current)::int
    UNION ALL
    SELECT 'C: has exactly one closed version', 1,
           (SELECT count(*) FROM h WHERE employer_key = 3
             AND NOT is_current AND valid_to = DATE '2026-02-01')::int
    UNION ALL
    SELECT 'D: added late, open from snapshot 2', 1,
           (SELECT count(*) FROM h WHERE employer_key = 4
             AND is_current AND valid_from = DATE '2026-02-01')::int
    UNION ALL
    SELECT 'no business key has two open versions', 0,
           (SELECT count(*) FROM (
                SELECT 1 FROM h WHERE is_current
                GROUP BY employer_key, route, location_key HAVING count(*) > 1) d)::int
) results
ORDER BY status DESC, check_name;

-- The fixture schema is left in place so the results above can be inspected.
-- It is dropped and rebuilt at the start of every run.
