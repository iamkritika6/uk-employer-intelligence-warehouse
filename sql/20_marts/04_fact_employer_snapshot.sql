-- fact_employer_snapshot: the central fact table.
--
-- Grain, stated explicitly because everything else depends on it:
--   one row per employer, per route, per location, per snapshot.
--
-- That is the grain of the published register itself. The same organisation
-- appears once for every route it is licensed on, which is why 143,220 rows
-- describe 126,963 employers.
--
-- This is a "periodic snapshot" fact table: it records the state of the
-- register on the day a file was published, not events that happened. There
-- is no measure to sum - the fact of the row existing is the measurement.
-- Counting rows counts licences; counting distinct employer_key counts
-- organisations. Confusing the two is the easiest mistake to make here.
--
-- snapshot_date is taken from the publisher's own filename rather than the
-- date the file was loaded, so re-running the pipeline cannot change history.

DROP TABLE IF EXISTS marts.fact_employer_snapshot CASCADE;

CREATE TABLE marts.fact_employer_snapshot (
    employer_snapshot_key bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employer_key   integer NOT NULL REFERENCES marts.dim_employer  (employer_key),
    location_key   integer NOT NULL REFERENCES marts.dim_location  (location_key),
    company_key    integer          REFERENCES marts.dim_company   (company_key),
    employer_type  text    NOT NULL,
    rating         text,
    route          text    NOT NULL,
    snapshot_date  date    NOT NULL,
    source_file    text    NOT NULL,
    -- How many published rows collapsed into this one. Greater than 1 means
    -- the register repeated the row; 772 such groups exist.
    source_row_count integer NOT NULL DEFAULT 1,
    -- True when those repeated rows disagreed about the rating. Recorded
    -- rather than resolved: there is no way to tell which is current, and
    -- quietly choosing one would hide a contradiction in the source.
    has_rating_conflict boolean NOT NULL DEFAULT false,

    -- The grain, enforced rather than described. If a future snapshot breaks
    -- this assumption the load fails loudly instead of double-counting.
    CONSTRAINT uq_fact_grain UNIQUE (employer_key, route, location_key, snapshot_date)
);

INSERT INTO marts.fact_employer_snapshot (
    employer_key, location_key, company_key,
    employer_type, rating, route, snapshot_date, source_file,
    source_row_count, has_rating_conflict
)
SELECT
    e.employer_key,
    l.location_key,
    c.company_key,
    min(s.employer_type),
    min(s.rating),
    s.route,
    -- The filename ends in the publication date, e.g.
    -- "..._Web_Register_-_2026-10-15.csv".
    to_date(substring(s.source_file from '(\d{4}-\d{2}-\d{2})'), 'YYYY-MM-DD'),
    s.source_file,
    count(*),
    count(DISTINCT s.rating) > 1
FROM staging.stg_licensed_employers s
JOIN marts.dim_employer e
  ON e.organisation_name_normalised = s.organisation_name_normalised
-- The unknown location member catches the single row with no town, so this
-- stays an inner join and location_key can be NOT NULL.
-- Joined on the case-folded keys, not the published spelling, so the four
-- spellings of London resolve to one location.
JOIN marts.dim_location l
  ON (l.town_key IS NOT DISTINCT FROM s.town_key
      AND l.county_key IS NOT DISTINCT FROM s.county_key
      AND NOT l.is_unknown)
  OR (s.town_key IS NULL AND l.is_unknown)
-- LEFT JOIN: most employers have no matched company, and a fact row must
-- survive that. company_key NULL means "not linked to Companies House", which
-- is a real and common state, not an error.
LEFT JOIN marts.employer_company_match m
  ON m.organisation_name_normalised = s.organisation_name_normalised
 AND m.company_number IS NOT NULL
LEFT JOIN marts.dim_company c
  ON c.company_number = m.company_number
GROUP BY e.employer_key, l.location_key, c.company_key, s.route, s.source_file;

CREATE INDEX ix_fact_employer  ON marts.fact_employer_snapshot (employer_key);
CREATE INDEX ix_fact_location  ON marts.fact_employer_snapshot (location_key);
CREATE INDEX ix_fact_company   ON marts.fact_employer_snapshot (company_key);
CREATE INDEX ix_fact_snapshot  ON marts.fact_employer_snapshot (snapshot_date);
