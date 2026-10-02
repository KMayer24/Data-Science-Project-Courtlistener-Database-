-- ============================================================
-- 02_validate_author_gender_step1_author_id.sql
--
-- Purpose:
--   Validate gender resolution via structured author_id (Step 1).
--
-- Input:
--   ext.author_gender_author_id
--
-- Prerequisite:
--   01_create_author_gender_step1_author_id.sql
-- ============================================================

\pset pager off
\timing on

-- ------------------------------------------------------------
-- 1. Does the table exist?
-- ------------------------------------------------------------

SELECT
    table_schema,
    table_name
FROM information_schema.tables
WHERE table_schema = 'ext'
  AND table_name = 'author_gender_author_id';


-- ------------------------------------------------------------
-- 2. Basic counts
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_opinions_with_author_id,
    COUNT(*) FILTER (WHERE gender_resolved) AS n_gender_resolved,
    COUNT(*) FILTER (WHERE NOT gender_resolved) AS n_gender_not_resolved,
    COUNT(DISTINCT author_id) AS n_distinct_authors,
    COUNT(DISTINCT court_id) AS n_courts
FROM ext.author_gender_author_id;


-- ------------------------------------------------------------
-- 3. Gender distribution
-- ------------------------------------------------------------

SELECT
    gender,
    gender_source,
    COUNT(*) AS n_opinions,
    COUNT(DISTINCT author_id) AS n_distinct_authors
FROM ext.author_gender_author_id
GROUP BY gender, gender_source
ORDER BY gender, gender_source;


-- ------------------------------------------------------------
-- 4. Check join back to federal appeals subset
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_mapping_rows,
    COUNT(fao.opinion_id) AS n_joined_to_federal_appeal_opinions,
    COUNT(*) - COUNT(fao.opinion_id) AS n_missing_in_federal_appeal_opinions
FROM ext.author_gender_author_id ag
LEFT JOIN ext.federal_appeal_opinions fao
    ON ag.opinion_id = fao.opinion_id;


-- ------------------------------------------------------------
-- 5. Check join back to people_db_person
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_mapping_rows,
    COUNT(p.id) AS n_joined_to_people,
    COUNT(*) - COUNT(p.id) AS n_missing_in_people
FROM ext.author_gender_author_id ag
LEFT JOIN public.people_db_person p
    ON ag.author_id = p.id;


-- ------------------------------------------------------------
-- 6. Distribution by court
-- ------------------------------------------------------------

SELECT
    court_id,
    court_short_name,
    COUNT(*) AS n_opinions_with_author_id,
    COUNT(*) FILTER (WHERE gender = 'f') AS n_female_authored,
    COUNT(*) FILTER (WHERE gender = 'm') AS n_male_authored,
    COUNT(DISTINCT author_id) AS n_distinct_authors
FROM ext.author_gender_author_id
GROUP BY court_id, court_short_name
ORDER BY court_id;


-- ------------------------------------------------------------
-- 7. Distribution by year
-- ------------------------------------------------------------

SELECT
    year_filed,
    COUNT(*) AS n_opinions_with_author_id,
    COUNT(*) FILTER (WHERE gender = 'f') AS n_female_authored,
    COUNT(*) FILTER (WHERE gender = 'm') AS n_male_authored,
    COUNT(DISTINCT author_id) AS n_distinct_authors
FROM ext.author_gender_author_id
GROUP BY year_filed
ORDER BY year_filed;


-- ------------------------------------------------------------
-- 8. Sample records
-- ------------------------------------------------------------

SELECT
    opinion_id,
    court_id,
    date_filed,
    case_name,
    author_id,
    author_str,
    name_first,
    name_middle,
    name_last,
    gender,
    gender_source
FROM ext.author_gender_author_id
ORDER BY date_filed DESC NULLS LAST
LIMIT 30;