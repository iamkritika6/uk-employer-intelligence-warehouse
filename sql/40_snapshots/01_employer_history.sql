-- Slowly Changing Dimension Type 2 history for employers.
--
-- The register is republished regularly. Each publication is a snapshot of
-- who holds a licence that day. SCD Type 2 turns a series of snapshots into a
-- history: instead of overwriting, a change closes the old row and opens a
-- new one, so the state at any past date can still be read.
--
--   valid_from  the snapshot this version first appeared in
--   valid_to    the snapshot it stopped being true; 9999-12-31 while current
--   is_current  convenience flag for "the version in force now"
--
-- Business key: (employer_key, route, location_key).
-- Tracked attributes: employer_type, rating.
--
-- Location belongs in the KEY, not in the tracked attributes, and getting
-- this wrong is how the first version of this file failed. The obvious key
-- is (employer_key, route) - but 796 employer/route pairs are published at
-- more than one town at the same time. 1st Choice Cabs Ltd, for instance,
-- appears under both Ilford and London for Skilled Worker. With location
-- outside the key those are two competing "current" rows for one key, and
-- the unique index rejected the load.
--
-- The consequence, stated plainly: an employer genuinely MOVING town is
-- recorded as one version closing and another opening, rather than as a
-- single version with a changed address. Distinguishing a move from a second
-- site is not possible from this data, and inventing a rule to guess would
-- be worse than the limitation.
--
-- A change to any tracked attribute creates a new version; an employer
-- vanishing from the register closes its version without opening another.
--
-- IMPORTANT, and stated here rather than discovered later: only ONE snapshot
-- has been loaded (2026-10-15). This logic is therefore exercised by the
-- fixture in tests/, not by real history. Loading a second published snapshot
-- is what would turn it into real change tracking. No history has been
-- invented to make the output look fuller.

-- Rebuilt from scratch on every run, deliberately.
--
-- The dimensions use GENERATED ALWAYS AS IDENTITY and are dropped and
-- recreated by the marts layer, so employer_key and location_key are reissued
-- on every full rebuild. History rows holding old key values would then point
-- at the wrong employers - silently, because the foreign keys would still
-- resolve.
--
-- Rebuilding is safe because nothing is lost: the fact table holds every
-- snapshot that has been loaded, and the pipeline replays them in publication
-- order, so the history is reconstructed identically.
--
-- The first version of this file used CREATE TABLE IF NOT EXISTS and survived
-- a full rebuild only by luck - the identity sequences happened to reissue the
-- same numbers because the inserts are deterministically ordered.
DROP TABLE IF EXISTS marts.employer_history CASCADE;

CREATE TABLE marts.employer_history (
    employer_history_key bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employer_key  integer NOT NULL REFERENCES marts.dim_employer (employer_key),
    route         text    NOT NULL,
    location_key  integer NOT NULL REFERENCES marts.dim_location (location_key),
    employer_type text    NOT NULL,
    rating        text,
    valid_from    date    NOT NULL,
    valid_to      date    NOT NULL DEFAULT DATE '9999-12-31',
    is_current    boolean NOT NULL DEFAULT true,

    CONSTRAINT ck_history_dates CHECK (valid_to >= valid_from),
    -- is_current must agree with valid_to; they cannot drift apart.
    CONSTRAINT ck_history_current CHECK (
        (is_current AND valid_to = DATE '9999-12-31')
        OR (NOT is_current AND valid_to < DATE '9999-12-31')
    )
);

-- At most one open version per business key. This is the constraint that
-- makes the whole pattern trustworthy: without it a bug in the load could
-- leave two "current" rows and every query would double-count.
CREATE UNIQUE INDEX IF NOT EXISTS uq_employer_history_current
    ON marts.employer_history (employer_key, route, location_key)
    WHERE is_current;


-- Applies one snapshot to the history table.
--
-- Takes a schema name so the same logic can run against the test fixture
-- without copying it. %I quotes the identifier safely; building SQL by
-- concatenating a bare string would be an injection risk even here.
CREATE OR REPLACE FUNCTION marts.apply_employer_snapshot(
    p_schema        text,
    p_snapshot_date date
)
RETURNS TABLE (closed_versions bigint, opened_versions bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_closed bigint;
    v_opened bigint;
BEGIN
    -- Step 1. Close any current version that the new snapshot does not
    -- confirm, either because the employer is gone or because a tracked
    -- attribute changed. valid_to is set to the snapshot date: the version
    -- was true up to, not beyond, this publication.
    EXECUTE format($sql$
        UPDATE %I.employer_history h
        SET valid_to = $1, is_current = false
        WHERE h.is_current
          AND NOT EXISTS (
              SELECT 1 FROM %I.fact_employer_snapshot f
              WHERE f.snapshot_date = $1
                AND f.employer_key  = h.employer_key
                AND f.route         = h.route
                AND f.location_key  = h.location_key
                AND f.employer_type = h.employer_type
                AND f.rating IS NOT DISTINCT FROM h.rating
          )
    $sql$, p_schema, p_schema) USING p_snapshot_date;
    GET DIAGNOSTICS v_closed = ROW_COUNT;

    -- Step 2. Open a version for anything in the snapshot that no current
    -- version already describes. Runs after step 1, so rows left open are
    -- exactly the unchanged ones and are skipped here.
    --
    -- This makes the function idempotent: applying the same snapshot twice
    -- closes nothing and opens nothing the second time.
    EXECUTE format($sql$
        INSERT INTO %I.employer_history
            (employer_key, route, location_key, employer_type, rating, valid_from)
        SELECT f.employer_key, f.route, f.location_key, f.employer_type, f.rating, $1
        FROM %I.fact_employer_snapshot f
        WHERE f.snapshot_date = $1
          AND NOT EXISTS (
              SELECT 1 FROM %I.employer_history h
              WHERE h.is_current
                AND h.employer_key  = f.employer_key
                AND h.route         = f.route
                AND h.location_key  = f.location_key
          )
    $sql$, p_schema, p_schema, p_schema) USING p_snapshot_date;
    GET DIAGNOSTICS v_opened = ROW_COUNT;

    RETURN QUERY SELECT v_closed, v_opened;
END;
$$;


-- Reading the history: what changed between two snapshots.
CREATE OR REPLACE VIEW marts.v_employer_changes AS
SELECT
    e.display_name,
    h.route,
    h.rating,
    h.valid_from,
    h.valid_to,
    CASE
        WHEN h.valid_from = (SELECT min(valid_from) FROM marts.employer_history)
            THEN 'present at first snapshot'
        WHEN h.is_current THEN 'added or changed'
        ELSE 'removed or superseded'
    END AS change_type
FROM marts.employer_history h
JOIN marts.dim_employer e ON e.employer_key = h.employer_key;
