-- ============================================================
-- 03_validate_corpus.sql
-- Purpose:
--   Validate ext.federal_appeal_opinions and verify that it
--   joins correctly to all relevant CourtListener tables.
--
--   Checks include:
--     - Table existence and row counts
--     - Text field availability (html_with_citations, plain_text)
--     - Court membership (exactly 13 target courts)
--     - Foreign key integrity (search_opinion, search_opinioncluster,
--       search_docket, search_court)
--     - Nature-of-suit coverage and consistency
--     - Joins to panel, citations, citation network,
--       joined_by, positions, education, political affiliation, race
--
-- Prerequisite:
--   02_create_federal_appeals_opinion_subset.sql
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
  AND table_name IN (
      'federal_appeal_courts',
      'federal_appeal_opinions',
      'federal_appeal_opinion_meta'
  )
ORDER BY table_name;


-- ------------------------------------------------------------
-- 2. Basic row counts
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_opinions,

    COUNT(*) FILTER (
        WHERE has_plain_text
    ) AS n_with_plain_text,

    COUNT(*) FILTER (
        WHERE has_html_with_citations
    ) AS n_with_html_with_citations,

    COUNT(*) FILTER (
        WHERE has_plain_text
          AND has_html_with_citations
    ) AS n_with_both_text_fields,

    COUNT(*) FILTER (
        WHERE NOT has_plain_text
          AND NOT has_html_with_citations
    ) AS n_with_neither_text_field,

    COUNT(*) FILTER (
        WHERE author_id IS NOT NULL
    ) AS n_with_author_id,

    COUNT(*) FILTER (
        WHERE author_str IS NOT NULL
          AND TRIM(author_str) <> ''
    ) AS n_with_author_str,

    COUNT(*) FILTER (
        WHERE cluster_nature_of_suit IS NOT NULL
          AND TRIM(cluster_nature_of_suit) <> ''
    ) AS n_with_cluster_nature_of_suit,

    COUNT(*) FILTER (
        WHERE docket_nature_of_suit IS NOT NULL
          AND TRIM(docket_nature_of_suit) <> ''
    ) AS n_with_docket_nature_of_suit,

    COUNT(*) FILTER (
        WHERE docket_cause IS NOT NULL
          AND TRIM(docket_cause) <> ''
    ) AS n_with_docket_cause,

    COUNT(*) FILTER (
        WHERE docket_jurisdiction_type IS NOT NULL
          AND TRIM(docket_jurisdiction_type) <> ''
    ) AS n_with_docket_jurisdiction_type

FROM ext.federal_appeal_opinions;


-- ------------------------------------------------------------
-- 3. Text availability by court
-- ------------------------------------------------------------

SELECT
    court_id,
    court_short_name,
    COUNT(*) AS n_opinions,

    COUNT(*) FILTER (
        WHERE has_plain_text
    ) AS n_with_plain_text,

    COUNT(*) FILTER (
        WHERE has_html_with_citations
    ) AS n_with_html_with_citations,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE has_plain_text
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_with_plain_text,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE has_html_with_citations
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_with_html_with_citations

FROM ext.federal_appeal_opinions
GROUP BY court_id, court_short_name
ORDER BY court_id;


-- ------------------------------------------------------------
-- 4. Text length summary
-- ------------------------------------------------------------

SELECT
    COUNT(*) FILTER (WHERE has_plain_text) AS n_with_plain_text,
    MIN(plain_text_length) FILTER (WHERE has_plain_text) AS min_plain_text_length,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY plain_text_length)
        FILTER (WHERE has_plain_text) AS median_plain_text_length,
    AVG(plain_text_length) FILTER (WHERE has_plain_text) AS avg_plain_text_length,
    MAX(plain_text_length) FILTER (WHERE has_plain_text) AS max_plain_text_length,

    COUNT(*) FILTER (WHERE has_html_with_citations) AS n_with_html_with_citations,
    MIN(html_with_citations_length) FILTER (WHERE has_html_with_citations) AS min_html_with_citations_length,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY html_with_citations_length)
        FILTER (WHERE has_html_with_citations) AS median_html_with_citations_length,
    AVG(html_with_citations_length) FILTER (WHERE has_html_with_citations) AS avg_html_with_citations_length,
    MAX(html_with_citations_length) FILTER (WHERE has_html_with_citations) AS max_html_with_citations_length

FROM ext.federal_appeal_opinions;


-- ------------------------------------------------------------
-- 5. Sample records with text availability
-- ------------------------------------------------------------

SELECT
    opinion_id,
    cluster_id,
    docket_id,
    court_id,
    date_filed,
    case_name,
    has_plain_text,
    plain_text_length,
    has_html_with_citations,
    html_with_citations_length
FROM ext.federal_appeal_opinions
WHERE has_plain_text
   OR has_html_with_citations
LIMIT 30;


-- ------------------------------------------------------------
-- 6. Make sure only the 13 target courts are present
-- ------------------------------------------------------------

SELECT
    court_id,
    court_short_name,
    COUNT(*) AS n_opinions
FROM ext.federal_appeal_opinions
GROUP BY court_id, court_short_name
ORDER BY court_id;


-- This should return 0 rows.
SELECT DISTINCT
    court_id
FROM ext.federal_appeal_opinions
WHERE court_id NOT IN (
    'ca1','ca2','ca3','ca4','ca5','ca6','ca7',
    'ca8','ca9','ca10','ca11','cadc','cafc'
);


-- ------------------------------------------------------------
-- 7. Check that opinion_id links back to public.search_opinion
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_subset_rows,
    COUNT(o.id) AS n_joined_to_search_opinion,
    COUNT(*) - COUNT(o.id) AS n_missing_in_search_opinion
FROM ext.federal_appeal_opinions fao
LEFT JOIN public.search_opinion o
    ON fao.opinion_id = o.id;


-- ------------------------------------------------------------
-- 8. Check that cluster_id links back to search_opinioncluster
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_subset_rows,
    COUNT(oc.id) AS n_joined_to_opinioncluster,
    COUNT(*) - COUNT(oc.id) AS n_missing_in_opinioncluster
FROM ext.federal_appeal_opinions fao
LEFT JOIN public.search_opinioncluster oc
    ON fao.cluster_id = oc.id;


-- ------------------------------------------------------------
-- 9. Check that docket_id links back to search_docket
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_subset_rows,
    COUNT(d.id) AS n_joined_to_docket,
    COUNT(*) - COUNT(d.id) AS n_missing_in_docket
FROM ext.federal_appeal_opinions fao
LEFT JOIN public.search_docket d
    ON fao.docket_id = d.id;


-- ------------------------------------------------------------
-- 10. Check that court_id links back to search_court
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_subset_rows,
    COUNT(c.id) AS n_joined_to_court,
    COUNT(*) - COUNT(c.id) AS n_missing_in_court
FROM ext.federal_appeal_opinions fao
LEFT JOIN public.search_court c
    ON fao.court_id = c.id;


-- ------------------------------------------------------------
-- 11. Can we get person information for structured authors?
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_opinions,
    COUNT(*) FILTER (WHERE fao.author_id IS NOT NULL) AS n_with_author_id,
    COUNT(p.id) AS n_joined_to_people,
    COUNT(*) FILTER (
        WHERE fao.author_id IS NOT NULL
          AND p.id IS NULL
    ) AS n_author_id_missing_in_people
FROM ext.federal_appeal_opinions fao
LEFT JOIN public.people_db_person p
    ON fao.author_id = p.id;


-- Sample joined author records
SELECT
    fao.opinion_id,
    fao.court_id,
    fao.date_filed,
    fao.case_name,
    fao.author_id,
    fao.author_str,
    p.name_first,
    p.name_middle,
    p.name_last,
    p.gender
FROM ext.federal_appeal_opinions fao
LEFT JOIN public.people_db_person p
    ON fao.author_id = p.id
WHERE fao.author_id IS NOT NULL
LIMIT 20;


-- ------------------------------------------------------------
-- 12. Check nature-of-suit availability overall
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_opinions,

    COUNT(*) FILTER (
        WHERE cluster_nature_of_suit IS NOT NULL
          AND TRIM(cluster_nature_of_suit) <> ''
    ) AS n_with_cluster_nature_of_suit,

    COUNT(*) FILTER (
        WHERE docket_nature_of_suit IS NOT NULL
          AND TRIM(docket_nature_of_suit) <> ''
    ) AS n_with_docket_nature_of_suit,

    COUNT(*) FILTER (
        WHERE cluster_nature_of_suit IS NOT NULL
          AND TRIM(cluster_nature_of_suit) <> ''
          AND docket_nature_of_suit IS NOT NULL
          AND TRIM(docket_nature_of_suit) <> ''
    ) AS n_with_both_nature_of_suit,

    COUNT(*) FILTER (
        WHERE (
            cluster_nature_of_suit IS NULL
            OR TRIM(cluster_nature_of_suit) = ''
        )
        AND (
            docket_nature_of_suit IS NULL
            OR TRIM(docket_nature_of_suit) = ''
        )
    ) AS n_with_neither_nature_of_suit,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE cluster_nature_of_suit IS NOT NULL
              AND TRIM(cluster_nature_of_suit) <> ''
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_with_cluster_nature_of_suit,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE docket_nature_of_suit IS NOT NULL
              AND TRIM(docket_nature_of_suit) <> ''
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_with_docket_nature_of_suit

FROM ext.federal_appeal_opinions;


-- ------------------------------------------------------------
-- 13. Check nature-of-suit availability by court
-- ------------------------------------------------------------

SELECT
    court_id,
    court_short_name,
    COUNT(*) AS n_opinions,

    COUNT(*) FILTER (
        WHERE cluster_nature_of_suit IS NOT NULL
          AND TRIM(cluster_nature_of_suit) <> ''
    ) AS n_with_cluster_nature_of_suit,

    COUNT(*) FILTER (
        WHERE docket_nature_of_suit IS NOT NULL
          AND TRIM(docket_nature_of_suit) <> ''
    ) AS n_with_docket_nature_of_suit,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE cluster_nature_of_suit IS NOT NULL
              AND TRIM(cluster_nature_of_suit) <> ''
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_with_cluster_nature_of_suit,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE docket_nature_of_suit IS NOT NULL
              AND TRIM(docket_nature_of_suit) <> ''
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_with_docket_nature_of_suit

FROM ext.federal_appeal_opinions
GROUP BY court_id, court_short_name
ORDER BY court_id;


-- ------------------------------------------------------------
-- 14. Check whether cluster and docket nature_of_suit differ
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_opinions,

    COUNT(*) FILTER (
        WHERE cluster_nature_of_suit IS NOT NULL
          AND TRIM(cluster_nature_of_suit) <> ''
          AND docket_nature_of_suit IS NOT NULL
          AND TRIM(docket_nature_of_suit) <> ''
          AND TRIM(cluster_nature_of_suit) = TRIM(docket_nature_of_suit)
    ) AS n_same_when_both_present,

    COUNT(*) FILTER (
        WHERE cluster_nature_of_suit IS NOT NULL
          AND TRIM(cluster_nature_of_suit) <> ''
          AND docket_nature_of_suit IS NOT NULL
          AND TRIM(docket_nature_of_suit) <> ''
          AND TRIM(cluster_nature_of_suit) <> TRIM(docket_nature_of_suit)
    ) AS n_different_when_both_present

FROM ext.federal_appeal_opinions;


-- ------------------------------------------------------------
-- 15. Most common cluster_nature_of_suit values
-- ------------------------------------------------------------

SELECT
    cluster_nature_of_suit,
    COUNT(*) AS n_opinions
FROM ext.federal_appeal_opinions
WHERE cluster_nature_of_suit IS NOT NULL
  AND TRIM(cluster_nature_of_suit) <> ''
GROUP BY cluster_nature_of_suit
ORDER BY n_opinions DESC
LIMIT 30;


-- ------------------------------------------------------------
-- 16. Most common docket_nature_of_suit values
-- ------------------------------------------------------------

SELECT
    docket_nature_of_suit,
    COUNT(*) AS n_opinions
FROM ext.federal_appeal_opinions
WHERE docket_nature_of_suit IS NOT NULL
  AND TRIM(docket_nature_of_suit) <> ''
GROUP BY docket_nature_of_suit
ORDER BY n_opinions DESC
LIMIT 30;


-- ------------------------------------------------------------
-- 17. Sample records with nature-of-suit variables
-- ------------------------------------------------------------

SELECT
    opinion_id,
    cluster_id,
    docket_id,
    court_id,
    date_filed,
    case_name,
    cluster_nature_of_suit,
    docket_nature_of_suit,
    docket_cause,
    docket_jurisdiction_type
FROM ext.federal_appeal_opinions
WHERE (
        cluster_nature_of_suit IS NOT NULL
        AND TRIM(cluster_nature_of_suit) <> ''
      )
   OR (
        docket_nature_of_suit IS NOT NULL
        AND TRIM(docket_nature_of_suit) <> ''
      )
LIMIT 30;


-- ------------------------------------------------------------
-- 18. Can we join to panel membership?
-- ------------------------------------------------------------

SELECT
    COUNT(DISTINCT fao.cluster_id) AS n_clusters_in_subset,
    COUNT(DISTINCT panel.opinioncluster_id) AS n_clusters_with_panel_data,
    COUNT(panel.person_id) AS n_panel_judge_rows
FROM ext.federal_appeal_opinions fao
LEFT JOIN public.search_opinioncluster_panel panel
    ON fao.cluster_id = panel.opinioncluster_id;


-- Sample panel records
SELECT
    fao.cluster_id,
    fao.court_id,
    fao.date_filed,
    fao.case_name,
    panel.person_id,
    p.name_first,
    p.name_last,
    p.gender
FROM ext.federal_appeal_opinions fao
JOIN public.search_opinioncluster_panel panel
    ON fao.cluster_id = panel.opinioncluster_id
LEFT JOIN public.people_db_person p
    ON panel.person_id = p.id
LIMIT 20;


-- ------------------------------------------------------------
-- 19. Can we join to citations?
-- ------------------------------------------------------------

SELECT
    COUNT(DISTINCT fao.cluster_id) AS n_clusters_in_subset,
    COUNT(cit.id) AS n_citation_rows
FROM ext.federal_appeal_opinions fao
LEFT JOIN public.search_citation cit
    ON fao.cluster_id = cit.cluster_id;


-- Sample citation records
SELECT
    fao.opinion_id,
    fao.cluster_id,
    fao.court_id,
    fao.case_name,
    cit.volume,
    cit.reporter,
    cit.page,
    cit.type
FROM ext.federal_appeal_opinions fao
JOIN public.search_citation cit
    ON fao.cluster_id = cit.cluster_id
LIMIT 20;


-- ------------------------------------------------------------
-- 20. Can we join to citation network?
-- ------------------------------------------------------------

SELECT
    (SELECT COUNT(*) FROM ext.federal_appeal_opinions) AS n_subset_opinions,

    (SELECT COUNT(*)
     FROM public.search_opinionscited ocit
     JOIN ext.federal_appeal_opinions fao
       ON fao.opinion_id = ocit.citing_opinion_id
    ) AS n_times_subset_opinions_cite_others,

    (SELECT COUNT(*)
     FROM public.search_opinionscited ocit
     JOIN ext.federal_appeal_opinions fao
       ON fao.opinion_id = ocit.cited_opinion_id
    ) AS n_times_subset_opinions_are_cited;


-- ------------------------------------------------------------
-- 21. Can we join to joined_by judges?
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_subset_opinions,
    COUNT(jb.person_id) AS n_joined_by_rows
FROM ext.federal_appeal_opinions fao
LEFT JOIN public.search_opinion_joined_by jb
    ON fao.opinion_id = jb.opinion_id;


-- Sample joined_by records
SELECT
    fao.opinion_id,
    fao.court_id,
    fao.date_filed,
    fao.case_name,
    jb.person_id,
    p.name_first,
    p.name_last,
    p.gender
FROM ext.federal_appeal_opinions fao
JOIN public.search_opinion_joined_by jb
    ON fao.opinion_id = jb.opinion_id
LEFT JOIN public.people_db_person p
    ON jb.person_id = p.id
LIMIT 20;


-- ------------------------------------------------------------
-- 22. Can we join to non-participating judges?
-- ------------------------------------------------------------

SELECT
    COUNT(DISTINCT fao.cluster_id) AS n_clusters_in_subset,
    COUNT(np.person_id) AS n_non_participating_judge_rows
FROM ext.federal_appeal_opinions fao
LEFT JOIN public.search_opinioncluster_non_participating_judges np
    ON fao.cluster_id = np.opinioncluster_id;


-- ------------------------------------------------------------
-- 23. Can we join to judge positions?
-- ------------------------------------------------------------

SELECT
    COUNT(DISTINCT fao.opinion_id) AS n_distinct_opinions_with_author_id,
    COUNT(DISTINCT fao.author_id) AS n_distinct_authors_with_id,
    COUNT(pos.id) AS n_author_position_join_rows,
    COUNT(DISTINCT pos.id) AS n_distinct_author_position_rows
FROM ext.federal_appeal_opinions fao
JOIN public.people_db_person p
    ON fao.author_id = p.id
LEFT JOIN public.people_db_position pos
    ON p.id = pos.person_id
WHERE fao.author_id IS NOT NULL;


-- Sample positions
SELECT
    fao.opinion_id,
    fao.court_id AS opinion_court_id,
    fao.date_filed,
    p.name_first,
    p.name_last,
    pos.job_title,
    pos.court_id AS position_court_id,
    pos.date_start,
    pos.date_termination,
    pos.termination_reason
FROM ext.federal_appeal_opinions fao
JOIN public.people_db_person p
    ON fao.author_id = p.id
LEFT JOIN public.people_db_position pos
    ON p.id = pos.person_id
WHERE fao.author_id IS NOT NULL
LIMIT 20;


-- ------------------------------------------------------------
-- 24. Can we join to education?
-- ------------------------------------------------------------

SELECT
    COUNT(DISTINCT fao.opinion_id) AS n_distinct_opinions_with_author_id,
    COUNT(DISTINCT fao.author_id) AS n_distinct_authors_with_id,
    COUNT(edu.id) AS n_education_join_rows,
    COUNT(DISTINCT edu.id) AS n_distinct_education_rows
FROM ext.federal_appeal_opinions fao
JOIN public.people_db_person p
    ON fao.author_id = p.id
LEFT JOIN public.people_db_education edu
    ON p.id = edu.person_id
WHERE fao.author_id IS NOT NULL;


-- Sample education
SELECT
    fao.author_id,
    p.name_first,
    p.name_last,
    edu.degree_level,
    edu.degree_detail,
    edu.degree_year,
    s.name AS school_name
FROM ext.federal_appeal_opinions fao
JOIN public.people_db_person p
    ON fao.author_id = p.id
LEFT JOIN public.people_db_education edu
    ON p.id = edu.person_id
LEFT JOIN public.people_db_school s
    ON edu.school_id = s.id
WHERE fao.author_id IS NOT NULL
LIMIT 20;


-- ------------------------------------------------------------
-- 25. Can we join to political affiliation?
-- ------------------------------------------------------------

SELECT
    COUNT(DISTINCT fao.opinion_id) AS n_distinct_opinions_with_author_id,
    COUNT(DISTINCT fao.author_id) AS n_distinct_authors_with_id,
    COUNT(pa.id) AS n_political_affiliation_join_rows,
    COUNT(DISTINCT pa.id) AS n_distinct_political_affiliation_rows
FROM ext.federal_appeal_opinions fao
JOIN public.people_db_person p
    ON fao.author_id = p.id
LEFT JOIN public.people_db_politicalaffiliation pa
    ON p.id = pa.person_id
WHERE fao.author_id IS NOT NULL;


-- ------------------------------------------------------------
-- 26. Can we join to race?
-- ------------------------------------------------------------

SELECT
    COUNT(DISTINCT fao.opinion_id) AS n_distinct_opinions_with_author_id,
    COUNT(DISTINCT fao.author_id) AS n_distinct_authors_with_id,
    COUNT(pr.id) AS n_person_race_join_rows,
    COUNT(DISTINCT pr.id) AS n_distinct_person_race_rows
FROM ext.federal_appeal_opinions fao
JOIN public.people_db_person p
    ON fao.author_id = p.id
LEFT JOIN public.people_db_person_race pr
    ON p.id = pr.person_id
LEFT JOIN public.people_db_race r
    ON pr.race_id = r.id
WHERE fao.author_id IS NOT NULL;


-- Sample race
SELECT
    fao.author_id,
    p.name_first,
    p.name_last,
    r.race
FROM ext.federal_appeal_opinions fao
JOIN public.people_db_person p
    ON fao.author_id = p.id
LEFT JOIN public.people_db_person_race pr
    ON p.id = pr.person_id
LEFT JOIN public.people_db_race r
    ON pr.race_id = r.id
WHERE fao.author_id IS NOT NULL
LIMIT 20;