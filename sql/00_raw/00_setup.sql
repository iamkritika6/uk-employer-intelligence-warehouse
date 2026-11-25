-- Creates the four schemas and the one extension the pipeline needs.
--
-- Every statement uses IF NOT EXISTS so the file can be run on every pipeline
-- run without failing on the second run (idempotent).

-- Raw layer: data exactly as downloaded. Every column text, nothing cleaned,
-- nothing dropped. Kept untouched so any later number can be traced back to
-- the file it came from.
CREATE SCHEMA IF NOT EXISTS raw;

-- Staging layer: the same data typed and cleaned. Dates become dates, numbers
-- become numbers, and organisation names are normalised into a form that can
-- be compared between the two sources.
CREATE SCHEMA IF NOT EXISTS staging;

-- Marts layer: the modelled star schema. Dimensions, a fact table and the
-- match table, with primary keys, foreign keys and constraints. This is the
-- layer the analysis queries read.
CREATE SCHEMA IF NOT EXISTS marts;

-- Analysis layer: a home for any helper views the analysis queries need. The
-- queries themselves live in sql/50_analysis as files, not as database objects.
CREATE SCHEMA IF NOT EXISTS analysis;

-- Trigram similarity, used in the matching phase to compare organisation names
-- that differ slightly between the two sources. Installed into public so it is
-- visible from every schema on the default search_path.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
