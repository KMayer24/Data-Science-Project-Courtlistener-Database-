-- ============================================================
-- 02_validate_fjc_judge_tables.sql
--
-- Purpose:
--   Validate the FJC judge tables loaded by
--   01_create_fjc_judge_tables.sql and inspect their suitability
--   for author-gender matching.
--
-- Tested tables:
--   ext.fjc_judge_bio
--   ext.fjc_judge_court
--
-- Prerequisite:
--   01_create_fjc_judge_tables.sql
-- ============================================================


\pset pager off
\timing on


-- ------------------------------------------------------------
-- 1. Do the tables exist?
-- ------------------------------------------------------------

SELECT
    table_schema,
    table_name
FROM information_schema.tables
WHERE table_schema = 'ext'
  AND table_name IN (
      'fjc_judge_bio',
      'fjc_judge_court'
  )
ORDER BY table_name;


-- ------------------------------------------------------------
-- 2. Basic biography counts
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_judges,
    COUNT(*) FILTER (WHERE gender = 'm') AS n_male,
    COUNT(*) FILTER (WHERE gender = 'f') AS n_female,
    COUNT(*) FILTER (WHERE gender IS NULL OR gender = '') AS n_missing_gender,
    COUNT(*) FILTER (WHERE race_or_ethnicity IS NOT NULL AND TRIM(race_or_ethnicity) <> '') AS n_with_race_or_ethnicity
FROM ext.fjc_judge_bio;


-- ------------------------------------------------------------
-- 3. Basic court-service counts
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_service_rows,
    COUNT(DISTINCT nid) AS n_distinct_judges_in_service,
    COUNT(*) FILTER (WHERE court_type = 'U.S. Court of Appeals') AS n_court_of_appeals_service_rows,
    COUNT(DISTINCT nid) FILTER (WHERE court_type = 'U.S. Court of Appeals') AS n_distinct_appeals_judges
FROM ext.fjc_judge_court;


-- ------------------------------------------------------------
-- 4. Check that every court-service row links to biography
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_service_rows,
    COUNT(b.nid) AS n_joined_to_bio,
    COUNT(*) - COUNT(b.nid) AS n_missing_in_bio
FROM ext.fjc_judge_court jc
LEFT JOIN ext.fjc_judge_bio b
    ON jc.nid = b.nid;


-- ------------------------------------------------------------
-- 5. Court types
-- ------------------------------------------------------------

SELECT
    court_type,
    COUNT(*) AS n_rows,
    COUNT(DISTINCT nid) AS n_distinct_judges
FROM ext.fjc_judge_court
GROUP BY court_type
ORDER BY n_rows DESC;


-- ------------------------------------------------------------
-- 6. Federal appeals courts in FJC service table
-- ------------------------------------------------------------

SELECT
    jc.court_name,
    COUNT(*) AS n_service_rows,
    COUNT(DISTINCT jc.nid) AS n_distinct_judges
FROM ext.fjc_judge_court jc
WHERE jc.court_type = 'U.S. Court of Appeals'
GROUP BY jc.court_name
ORDER BY jc.court_name;


-- ------------------------------------------------------------
-- 7. Sample appeals judges with biography
-- ------------------------------------------------------------

SELECT
    b.nid,
    b.jid,
    b.first_name,
    b.middle_name,
    b.last_name,
    b.suffix,
    b.gender,
    b.race_or_ethnicity,
    jc.appointment_seq,
    jc.court_type,
    jc.court_name,
    jc.commission_date,
    jc.termination,
    jc.termination_date
FROM ext.fjc_judge_bio b
JOIN ext.fjc_judge_court jc
    ON b.nid = jc.nid
WHERE jc.court_type = 'U.S. Court of Appeals'
ORDER BY jc.court_name, b.last_name, b.first_name, jc.appointment_seq
LIMIT 30;


-- ------------------------------------------------------------
-- 8. Check possible duplicate biography rows
--    This should return 0 rows because nid is primary key.
-- ------------------------------------------------------------

SELECT
    nid,
    COUNT(*) AS n_rows
FROM ext.fjc_judge_bio
GROUP BY nid
HAVING COUNT(*) > 1;


-- ------------------------------------------------------------
-- 9. Check possible duplicate service rows
--    Multiple rows per judge are expected when a judge served
--    on more than one court or had multiple appointments.
-- ------------------------------------------------------------

SELECT
    nid,
    judge_name,
    COUNT(*) AS n_service_rows
FROM ext.fjc_judge_court
GROUP BY nid, judge_name
HAVING COUNT(*) > 1
ORDER BY n_service_rows DESC, judge_name
LIMIT 30;


-- ------------------------------------------------------------
-- 10. Gender coverage among appeals judges
-- ------------------------------------------------------------

SELECT
    b.gender,
    COUNT(*) AS n_service_rows,
    COUNT(DISTINCT b.nid) AS n_distinct_judges
FROM ext.fjc_judge_court jc
JOIN ext.fjc_judge_bio b
    ON jc.nid = b.nid
WHERE jc.court_type = 'U.S. Court of Appeals'
GROUP BY b.gender
ORDER BY b.gender;


-- ------------------------------------------------------------
-- 11. Name fields useful for matching
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_appeals_service_rows,
    COUNT(*) FILTER (WHERE b.last_name IS NOT NULL AND TRIM(b.last_name) <> '') AS n_with_last_name,
    COUNT(*) FILTER (WHERE b.first_name IS NOT NULL AND TRIM(b.first_name) <> '') AS n_with_first_name,
    COUNT(*) FILTER (WHERE jc.court_name IS NOT NULL AND TRIM(jc.court_name) <> '') AS n_with_court_name
FROM ext.fjc_judge_court jc
JOIN ext.fjc_judge_bio b
    ON jc.nid = b.nid
WHERE jc.court_type = 'U.S. Court of Appeals';


-- ------------------------------------------------------------
-- 12. Names that are ambiguous within the same appeals court
--     These are important because author_str often contains only
--     a last name. Ambiguous last names cannot be safely matched
--     without further information.
-- ------------------------------------------------------------

SELECT
    jc.court_name,
    LOWER(TRIM(b.last_name)) AS last_name_norm,
    COUNT(DISTINCT b.nid) AS n_judges,
    STRING_AGG(
        b.first_name || ' ' || COALESCE(b.middle_name || ' ', '') || b.last_name,
        '; '
        ORDER BY b.first_name, b.middle_name, b.last_name
    ) AS candidate_names
FROM ext.fjc_judge_court jc
JOIN ext.fjc_judge_bio b
    ON jc.nid = b.nid
WHERE jc.court_type = 'U.S. Court of Appeals'
  AND b.last_name IS NOT NULL
  AND TRIM(b.last_name) <> ''
GROUP BY jc.court_name, LOWER(TRIM(b.last_name))
HAVING COUNT(DISTINCT b.nid) > 1
ORDER BY n_judges DESC, jc.court_name, last_name_norm
LIMIT 50;