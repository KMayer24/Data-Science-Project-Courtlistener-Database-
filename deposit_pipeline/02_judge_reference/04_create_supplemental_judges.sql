-- ============================================================
-- 04_create_supplemental_judges.sql
--
-- Purpose:
--   Create and populate ext.supplemental_judges — a manually
--   curated table of judges missing from the CourtListener and
--   FJC sources for specific circuit courts.
--
--   Three classes of judges are covered:
--
--   A. Name-change cases
--      The judge is in CourtListener but opinions use a different
--      name. Example: Priscilla Owen → Priscilla Richman (ca5,
--      from ~2023 onward).
--
--   B. By-designation judges
--      Judges from district courts or other circuits sitting by
--      designation on a circuit panel. FJC records only their
--      home court, not the circuit where they authored opinions.
--
--   C. Missing circuit positions
--      The judge is in people_db_person but the circuit position
--      was not imported into people_db_position.
--
--   This table forms the third branch of the unified judge pool
--   used in all downstream all_judges CTEs:
--     (1) people_db_person + people_db_position  [CourtListener]
--     (2) fjc_judge_bio + fjc_judge_court        [FJC fallback]
--     (3) supplemental_judges                    [manual additions]
--
-- Output:
--   ext.supplemental_judges
--
-- Prerequisite:
--   03_create_fjc_court_name_map.sql
--
-- Maintenance:
--   Add rows as new gaps are confirmed. Each row must include a
--   reason note for auditability:
--     'name_change:<CL_record_reference>'
--     'by_designation:home=<court_id>;observed_<years>'
--     'missing_cl_position'
-- ============================================================

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.supplemental_judges;

CREATE TABLE ext.supplemental_judges (
    sup_id      SERIAL PRIMARY KEY,
    name_first  TEXT,
    name_middle TEXT,
    name_last   TEXT        NOT NULL,
    gender      CHAR(1)     NOT NULL CHECK (gender IN ('m','f')),
    court_id    TEXT        NOT NULL,
    start_date  DATE,
    end_date    DATE,
    reason      TEXT    NOT NULL    -- audit note, e.g. 'name_change:...', 'by_designation:...'
);

-- ============================================================
-- A. Name-change cases
--    Judge is in CL/FJC under a different last name than appears
--    in opinions.  Add one row per name variant per court.
-- ============================================================

-- Priscilla Owen / Richman (ca5)
--   CL record: people_db_person id=2480, name_last='Owen', gender='f', fjc_id=3087
--   FJC record: nid=1392271, last_name='Richman', commission 2005-06-03
--   Opinions filed after ~2023 use her married name "Richman".
INSERT INTO ext.supplemental_judges
    (name_first, name_last, gender, court_id, start_date, reason)
VALUES
    ('Priscilla', 'Richman', 'f', 'ca5', '2005-06-03', 'name_change:CL_Owen_id2480');

-- ============================================================
-- B. By-designation judges
--    Judges from other courts sitting by designation on a circuit
--    panel.  FJC only records their home court; these rows add
--    them explicitly for the circuit(s) where they authored opinions.
--    Gender confirmed via FJC home-court record.
--    start_date = earliest observed opinion date (not an official
--    designation date — those are not tracked in FJC).
--    end_date = NULL means no known termination in the data.
-- ============================================================

INSERT INTO ext.supplemental_judges
    (name_first, name_last, gender, court_id, start_date, reason)
VALUES
    -- Jed S. Rakoff (SDNY) → ca9 by designation (observed 2012–2025)
    ('Jed',    'Rakoff',   'm', 'ca9', '2012-01-01', 'by_designation:home=sdny;observed_2012_2025'),
    -- Jed S. Rakoff (SDNY) → ca2 by designation (SDNY lies in 2nd Circuit;
    --   ca2 opinions observed, likely visiting panels)
    ('Jed',    'Rakoff',   'm', 'ca2', '2020-01-01', 'by_designation:home=sdny;observed_ca2'),
    -- Danny J. Boggs (ca6) → ca9 by designation (observed 2020–2023)
    ('Danny',  'Boggs',    'm', 'ca9', '2020-01-01', 'by_designation:home=ca6;observed_2020_2023'),
    -- Ronald Lee Gilman (ca6) → ca9 by designation (observed 2020–2024)
    ('Ronald', 'Gilman',   'm', 'ca9', '2020-01-01', 'by_designation:home=ca6;observed_2020_2024'),
    -- Eugene E. Siler Jr. (ca6) → ca9 by designation (observed 2020–2024)
    ('Eugene', 'Siler',    'm', 'ca9', '2020-01-01', 'by_designation:home=ca6;observed_2020_2024'),
    -- Edward R. Korman (EDNY) → ca2 by designation (EDNY lies in 2nd Circuit;
    --   observed 2020–2024)
    ('Edward', 'Korman',   'm', 'ca2', '2020-01-01', 'by_designation:home=edny;observed_2020_2024'),
    -- Evan J. Wallach (cafc) → ca9 by designation (observed 2022–2025)
    ('Evan',   'Wallach',  'm', 'ca9', '2022-01-01', 'by_designation:home=cafc;observed_2022_2025');
-- NOTE: Laurence Silberman (cadc) is NOT needed here.
--   He is in fjc_judge_bio with court_id='cadc' and is NOT blocked by the
--   court-scoped NOT EXISTS filter (his CL position is 'dcd', not 'cadc').
--   The FJC fallback branch already covers him.

COMMIT;

CREATE INDEX IF NOT EXISTS idx_supplemental_judges_court_id
    ON ext.supplemental_judges(court_id);

CREATE INDEX IF NOT EXISTS idx_supplemental_judges_last_name
    ON ext.supplemental_judges(LOWER(name_last));

ANALYZE ext.supplemental_judges;

-- ------------------------------------------------------------
-- Verification: show all rows
-- ------------------------------------------------------------
SELECT
    sup_id,
    name_first,
    name_middle,
    name_last,
    gender,
    court_id,
    start_date,
    end_date,
    reason
FROM ext.supplemental_judges
ORDER BY court_id, name_last, name_first;
