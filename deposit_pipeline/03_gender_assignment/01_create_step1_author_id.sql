-- ============================================================
-- 01_create_author_gender_step1_author_id.sql
--
-- Purpose:
--   Resolve author gender for Federal Appeals opinions using
--   the structured CourtListener author_id field (Step 1).
--
-- Method:
--   ext.federal_appeal_opinions.author_id
--       -> public.people_db_person.id
--       -> public.people_db_person.gender
--
-- Output:
--   ext.author_gender_author_id
--
-- Note:
--   This is the highest-confidence gender source because it uses
--   an explicit database link rather than name-based matching.
--
-- Prerequisite:
--   02_create_federal_appeals_opinions.sql (01_corpus_selection)
-- ============================================================

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.author_gender_author_id;

CREATE TABLE ext.author_gender_author_id AS
SELECT
    fao.opinion_id,
    fao.cluster_id,
    fao.docket_id,
    fao.court_id,
    fao.court_short_name,
    fao.date_filed,
    fao.year_filed,
    fao.case_name,

    fao.author_id,
    fao.author_str,

    p.name_first,
    p.name_middle,
    p.name_last,
    p.gender,

    CASE
        WHEN p.gender IN ('m', 'f') THEN 'author_id'
        ELSE 'author_id_no_valid_gender'
    END AS gender_source,

    CASE
        WHEN p.gender IN ('m', 'f') THEN true
        ELSE false
    END AS gender_resolved

FROM ext.federal_appeal_opinions fao
LEFT JOIN public.people_db_person p
    ON fao.author_id = p.id
WHERE fao.author_id IS NOT NULL;

ALTER TABLE ext.author_gender_author_id
ADD PRIMARY KEY (opinion_id);

CREATE INDEX idx_author_gender_author_id_author_id
    ON ext.author_gender_author_id(author_id);

CREATE INDEX idx_author_gender_author_id_court_id
    ON ext.author_gender_author_id(court_id);

CREATE INDEX idx_author_gender_author_id_gender
    ON ext.author_gender_author_id(gender);

CREATE INDEX idx_author_gender_author_id_year
    ON ext.author_gender_author_id(year_filed);

COMMIT;