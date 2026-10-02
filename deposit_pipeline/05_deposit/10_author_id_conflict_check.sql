-- ============================================================
-- 10_author_id_conflict_check.sql
--
-- Does CourtListener's structured author_id agree with the author name
-- recorded on the same opinion?
--
-- Why this matters: the attribution cascade treats the structured
-- author_id as the most reliable source and lets it override the
-- recorded name. Two opinions drawn into the manual validation sample
-- contradicted that assumption -- the text named Augustus N. Hand as the
-- author while author_id pointed to Thomas Swan:
--
--   opinion 1564887, United States v. Kelly (1932, ca2)
--     text: "AUGUSTUS N. HAND, Circuit Judge."   author_str: Hand
--     author_id 3146 -> Thomas Walter Swan
--   opinion 1498099, Exner v. Sherman Power Const. Co. (1931, ca2)
--     text: "... AUGUSTUS N. HAND, Circuit Judge."  author_str: empty
--     author_id 3146 -> Thomas Walter Swan
--
-- This script measures how widespread the disagreement is. It counts
-- CONFLICTS, not errors: only reading the opinion establishes which of
-- the two fields is wrong. The manual validation sample settles that.
-- ============================================================

\pset pager off

WITH step1 AS (
    SELECT
        h.opinion_id,
        h.court_id,
        h.author_str,
        p.gender     AS link_gender,
        p.name_last  AS link_last,
        lower(regexp_replace(regexp_replace(h.author_str, '[^A-Za-z\s-]', '', 'g'),
                             '\s+', ' ', 'g')) AS str_norm
    FROM ext.author_gender_final_with_html h
    JOIN public.people_db_person p ON p.id = h.author_id
    WHERE h.author_id IS NOT NULL
      AND btrim(coalesce(h.author_str, '')) <> ''
),
conflict AS (
    SELECT * FROM step1 WHERE str_norm NOT LIKE '%' || lower(link_last) || '%'
)

\echo '== How often do the two fields disagree? =='
SELECT count(*)                                              AS opinions_with_both_fields,
       (SELECT count(*) FROM conflict)                       AS surname_conflicts,
       round(100.0 * (SELECT count(*) FROM conflict) / count(*), 1) AS pct_conflict
FROM step1;

\echo ''
\echo '== The recurring pairs (same court, same era -- looks systematic) =='
SELECT author_str, link_last, count(*) AS n
FROM conflict GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 20;

\echo ''
\echo '== Would the recorded gender differ? =='
WITH named AS (
    SELECT c.opinion_id, c.link_gender,
           count(DISTINCT pj.gender) AS n_gender_for_text_name,
           min(pj.gender)            AS gender_for_text_name
    FROM conflict c
    JOIN public.people_db_position pos ON pos.court_id = c.court_id
    JOIN public.people_db_person   pj  ON pj.id = pos.person_id
    WHERE lower(pj.name_last) = c.str_norm AND pj.gender IS NOT NULL
    GROUP BY 1, 2
)
SELECT count(*)                                                          AS conflicts_with_identifiable_text_name,
       count(*) FILTER (WHERE n_gender_for_text_name = 1
                          AND gender_for_text_name = link_gender)        AS same_gender,
       count(*) FILTER (WHERE n_gender_for_text_name = 1
                          AND gender_for_text_name <> link_gender)       AS different_gender,
       count(*) FILTER (WHERE n_gender_for_text_name > 1)                AS text_name_ambiguous
FROM named;
