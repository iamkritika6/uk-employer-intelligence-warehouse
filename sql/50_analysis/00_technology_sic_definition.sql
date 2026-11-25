-- The definition of "technology sector" used by every query in this folder.
--
-- There is no official SIC code that means "technology", so any analysis using
-- the phrase has to choose, and the choice changes the answer. Putting it in a
-- table rather than repeating a list of codes in nine queries means there is
-- one definition, it can be read by anyone, and changing it changes every
-- result consistently.
--
-- Codes are matched by prefix, because SIC 2007 is hierarchical: 62 is a
-- division, 582 a group, 62012 a class.

DROP TABLE IF EXISTS analysis.technology_sic;

CREATE TABLE analysis.technology_sic (
    sic_prefix text PRIMARY KEY,
    label      text NOT NULL,
    rationale  text NOT NULL
);

INSERT INTO analysis.technology_sic (sic_prefix, label, rationale) VALUES
  ('26',  'Computer, electronic and optical manufacturing',
          'Hardware manufacture'),
  ('582', 'Software publishing',
          'Group 582 only. Division 58 as a whole is publishing, and includes book and newspaper publishing, which are not technology'),
  ('61',  'Telecommunications',
          'Network and communications operators'),
  ('62',  'Computer programming, consultancy and related activities',
          'The core software division: 62012 development, 62020 IT consultancy, 62090 other IT services'),
  ('63',  'Information service activities',
          'Data processing, hosting, web portals');

-- Deliberately excluded, and why:
--   71  Architectural and engineering activities - engineering services, not
--       technology in the sense meant here
--   72  Scientific research and development - research, often but not always
--       technological; including it would mix pharmaceutical and biological
--       research into a count described as "technology"
--   70229 Management consultancy - large and generic; many IT consultancies
--       register under it, but so does everything else
--
-- Those three are the borderline cases. A different analyst could justify
-- including 72, which would add roughly 900 employers. The point is that the
-- choice is visible rather than buried in a WHERE clause.

CREATE OR REPLACE VIEW analysis.v_technology_company AS
SELECT c.*
FROM marts.dim_company c
JOIN analysis.technology_sic t
  ON left(c.sic_code_1, length(t.sic_prefix)) = t.sic_prefix
-- Only exact name matches. Fuzzy matches are wrong at least 21% of the time
-- (docs/match_sample_check.md), and a sector label is exactly the kind of
-- attribute a wrong match corrupts: the SIC code would come from a different
-- company entirely.
WHERE c.match_method = 'exact';
