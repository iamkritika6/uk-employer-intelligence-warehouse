-- Raw table for the licensed employer register.
--
-- Column names are the file's own header, converted to snake_case:
--   "Organisation Name" -> organisation_name
--   "Town/City"         -> town_city
--   "County"            -> county
--   "Type & Rating"     -> type_and_rating
--   "Route"             -> route
-- Renamed only because the original names contain spaces, a slash and an
-- ampersand, which would have to be double-quoted in every later query.
--
-- Every column is text on purpose. A single unexpected character in a typed
-- column would abort the load of the whole file; text always loads, and
-- deciding what counts as malformed is the staging layer's job.
--
-- source_file and loaded_at are not in the file. They record which download a
-- row came from, which is what makes more than one snapshot possible.

CREATE TABLE IF NOT EXISTS raw.licensed_employers (
    organisation_name  text,
    town_city          text,
    county             text,
    type_and_rating    text,
    route              text,
    source_file        text,
    loaded_at          timestamptz DEFAULT now()
);

-- One row per organisation per route per snapshot, so the same file must never
-- be loaded twice. This index is what the loader checks before copying.
CREATE INDEX IF NOT EXISTS ix_raw_licensed_employers_source_file
    ON raw.licensed_employers (source_file);
