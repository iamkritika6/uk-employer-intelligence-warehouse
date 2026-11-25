-- Organisation name normalisation.
--
-- The two sources write the same organisation differently:
--
--   register        "Asian African Foods Ltd "
--   Companies House "ASIAN AFRICAN FOODS LIMITED"
--
-- Nothing matches those two strings until they are reduced to a common form.
-- This function is that common form, and both staging tables call it, so the
-- rules cannot drift apart between the two sides.
--
-- IMMUTABLE tells PostgreSQL the function always returns the same output for
-- the same input, which is what allows it to be used in an index later.
--
-- Written as a chain of named steps rather than nested function calls. Nesting
-- hid a real bug: whitespace was collapsed *after* legal suffixes were
-- stripped, so " Asian African Foods Ltd " still had a trailing space when the
-- suffix pattern ran, the pattern is anchored to the end of the string, and
-- "ltd" therefore survived. Order of operations is the whole game here.

CREATE OR REPLACE FUNCTION staging.normalise_org_name(raw_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    WITH lowered AS (
        -- 1. Case differs between the two sources.
        SELECT lower(coalesce(raw_name, '')) AS s
    ),
    ampersand_spelled_out AS (
        -- 2. "&" and "and" are both used. Spell it out before the next step
        --    deletes the symbol entirely.
        SELECT replace(s, '&', ' and ') AS s FROM lowered
    ),
    punctuation_removed AS (
        -- 3. Anything that is not a letter, digit or space becomes a space.
        --    A space, not nothing: "a.b.c" must become "a b c", not "abc".
        SELECT regexp_replace(s, '[^a-z0-9 ]', ' ', 'g') AS s
        FROM ampersand_spelled_out
    ),
    whitespace_tidied AS (
        -- 4. Collapse runs of spaces and trim the ends. This MUST happen
        --    before suffix stripping, because that pattern is anchored to the
        --    end of the string and a trailing space defeats it.
        SELECT btrim(regexp_replace(s, '\s+', ' ', 'g')) AS s
        FROM punctuation_removed
    ),
    suffixes_stripped AS (
        -- 5. Strip legal suffixes from the end, repeatedly:
        --    "trading co ltd" loses "ltd", then "co".
        SELECT btrim(regexp_replace(
                   s,
                   '( (limited|ltd|plc|llp|lp|cic|cio|company|co|inc|incorporated))+$',
                   '',
                   'g'
               )) AS s
        FROM whitespace_tidied
    )
    -- 6. If stripping suffixes emptied the name completely, keep the
    --    unstripped version instead. A company really is named "! LTD", and
    --    reducing it to nothing would drop it from matching altogether.
    SELECT nullif(
               coalesce(nullif(suffixes_stripped.s, ''), whitespace_tidied.s),
               ''
           )
    FROM whitespace_tidied, suffixes_stripped;
$$;

-- Deliberately NOT stripped: "uk", "group", "holdings", "services". These
-- distinguish genuinely different organisations - "Acme UK" and "Acme Group"
-- are not the same company - so removing them would manufacture false matches
-- rather than fix missed ones.
