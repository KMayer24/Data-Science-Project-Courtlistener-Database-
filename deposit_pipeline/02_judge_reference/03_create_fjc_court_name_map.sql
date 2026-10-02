-- ============================================================
-- 03_create_fjc_court_name_map.sql
--
-- Purpose:
--   Map Federal Judicial Center Court of Appeals names to
--   CourtListener court IDs.
--
--   FJC uses full court names, e.g.:
--     U.S. Court of Appeals for the First Circuit
--
--   CourtListener uses compact court IDs, e.g.:
--     ca1
--
--   This mapping is required for court-specific author-gender
--   matching in Steps~2--4.
--
-- Input:
--   ext.federal_appeal_courts
--   ext.fjc_judge_court
--
-- Output:
--   ext.fjc_court_name_map
--
-- Prerequisite:
--   01_create_fjc_judge_tables.sql
-- ============================================================

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.fjc_court_name_map;

CREATE TABLE ext.fjc_court_name_map (
    court_id varchar(15) PRIMARY KEY,
    court_short_name text,
    court_full_name text,
    fjc_court_name text NOT NULL,
    mapping_note text
);

INSERT INTO ext.fjc_court_name_map (
    court_id,
    court_short_name,
    court_full_name,
    fjc_court_name,
    mapping_note
)
SELECT
    c.id AS court_id,
    c.short_name AS court_short_name,
    c.full_name AS court_full_name,
    v.fjc_court_name,
    'manual one-to-one mapping between CourtListener court ID and FJC Court of Appeals name' AS mapping_note
FROM ext.federal_appeal_courts c
JOIN (
    VALUES
        ('ca1',  'U.S. Court of Appeals for the First Circuit'),
        ('ca2',  'U.S. Court of Appeals for the Second Circuit'),
        ('ca3',  'U.S. Court of Appeals for the Third Circuit'),
        ('ca4',  'U.S. Court of Appeals for the Fourth Circuit'),
        ('ca5',  'U.S. Court of Appeals for the Fifth Circuit'),
        ('ca6',  'U.S. Court of Appeals for the Sixth Circuit'),
        ('ca7',  'U.S. Court of Appeals for the Seventh Circuit'),
        ('ca8',  'U.S. Court of Appeals for the Eighth Circuit'),
        ('ca9',  'U.S. Court of Appeals for the Ninth Circuit'),
        ('ca10', 'U.S. Court of Appeals for the Tenth Circuit'),
        ('ca11', 'U.S. Court of Appeals for the Eleventh Circuit'),
        ('cadc', 'U.S. Court of Appeals for the District of Columbia Circuit'),
        ('cafc', 'U.S. Court of Appeals for the Federal Circuit')
) AS v(court_id, fjc_court_name)
    ON c.id = v.court_id;

CREATE INDEX idx_fjc_court_name_map_fjc_name
    ON ext.fjc_court_name_map(fjc_court_name);

COMMIT;


-- ------------------------------------------------------------
-- Output checks
-- ------------------------------------------------------------

SELECT
    court_id,
    court_short_name,
    court_full_name,
    fjc_court_name
FROM ext.fjc_court_name_map
ORDER BY court_id;


-- Should return 13
SELECT
    COUNT(*) AS n_mapped_courts
FROM ext.fjc_court_name_map;


-- Should return 0 rows:
-- CourtListener federal appeals courts without FJC mapping
SELECT
    c.id,
    c.short_name,
    c.full_name
FROM ext.federal_appeal_courts c
LEFT JOIN ext.fjc_court_name_map m
    ON c.id = m.court_id
WHERE m.court_id IS NULL;


-- Should return 0 rows:
-- FJC Court of Appeals names used in mapping but not found in FJC data
SELECT
    m.court_id,
    m.fjc_court_name
FROM ext.fjc_court_name_map m
LEFT JOIN (
    SELECT DISTINCT court_name
    FROM ext.fjc_judge_court
    WHERE court_type = 'U.S. Court of Appeals'
) jc
    ON m.fjc_court_name = jc.court_name
WHERE jc.court_name IS NULL;