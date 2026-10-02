-- ============================================================
-- 04_validate_author_gender_step2_author_str.sql
--
-- Purpose:
--   Validate gender resolution via author_str matching (Step 2).
--
-- Input:
--   ext.author_gender_author_str_fjc
--
-- Prerequisite:
--   03_create_author_gender_step2_author_str.sql
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
  AND table_name = 'author_gender_author_str_fjc';


-- ------------------------------------------------------------
-- 2. Basic counts
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_author_str_candidate_opinions,

    COUNT(*) FILTER (
        WHERE gender_resolved
    ) AS n_gender_resolved,

    COUNT(*) FILTER (
        WHERE NOT gender_resolved
    ) AS n_gender_not_resolved,

    COUNT(*) FILTER (
        WHERE gender_source = 'ambiguous_multiple_genders'
    ) AS n_ambiguous_multiple_genders,

    COUNT(*) FILTER (
        WHERE gender_source = 'no_fjc_match'
    ) AS n_no_fjc_match,

    COUNT(*) FILTER (
        WHERE gender_source = 'no_usable_author_str'
    ) AS n_no_usable_author_str,

    COUNT(DISTINCT author_last_name_norm) AS n_distinct_author_str_last_names,

    COUNT(DISTINCT court_id) AS n_courts

FROM ext.author_gender_author_str_fjc;


-- ------------------------------------------------------------
-- 3. Match-source distribution
-- ------------------------------------------------------------

SELECT
    gender_source,
    gender_resolved,
    COUNT(*) AS n_opinions,
    ROUND(
        100.0 * COUNT(*) / NULLIF(
            (SELECT COUNT(*) FROM ext.author_gender_author_str_fjc),
            0
        ),
        2
    ) AS pct_of_author_str_candidates
FROM ext.author_gender_author_str_fjc
GROUP BY gender_source, gender_resolved
ORDER BY n_opinions DESC;


-- ------------------------------------------------------------
-- 4. Gender distribution among resolved author_str-FJC matches
-- ------------------------------------------------------------

SELECT
    gender,
    COUNT(*) AS n_opinions,
    COUNT(DISTINCT author_last_name_norm) AS n_distinct_matched_last_names,
    ROUND(
        100.0 * COUNT(*) / NULLIF(
            (
                SELECT COUNT(*)
                FROM ext.author_gender_author_str_fjc
                WHERE gender_resolved
            ),
            0
        ),
        2
    ) AS pct_of_resolved_author_str_matches
FROM ext.author_gender_author_str_fjc
WHERE gender_resolved
GROUP BY gender
ORDER BY gender;


-- ------------------------------------------------------------
-- 5. Candidate judge count distribution
-- ------------------------------------------------------------

SELECT
    n_candidate_judges,
    n_candidate_genders,
    gender_source,
    COUNT(*) AS n_opinions
FROM ext.author_gender_author_str_fjc
GROUP BY
    n_candidate_judges,
    n_candidate_genders,
    gender_source
ORDER BY
    n_candidate_judges,
    n_candidate_genders,
    gender_source;


-- ------------------------------------------------------------
-- 6. Distribution by court
-- ------------------------------------------------------------

SELECT
    court_id,
    court_short_name,
    COUNT(*) AS n_author_str_candidate_opinions,

    COUNT(*) FILTER (
        WHERE gender_resolved
    ) AS n_gender_resolved,

    COUNT(*) FILTER (
        WHERE gender = 'f'
    ) AS n_female_authored,

    COUNT(*) FILTER (
        WHERE gender = 'm'
    ) AS n_male_authored,

    COUNT(*) FILTER (
        WHERE gender_source = 'ambiguous_multiple_genders'
    ) AS n_ambiguous_multiple_genders,

    COUNT(*) FILTER (
        WHERE gender_source = 'no_fjc_match'
    ) AS n_no_fjc_match,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE gender_resolved
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_gender_resolved

FROM ext.author_gender_author_str_fjc
GROUP BY court_id, court_short_name
ORDER BY court_id;


-- ------------------------------------------------------------
-- 7. Distribution by year
-- ------------------------------------------------------------

SELECT
    year_filed,
    COUNT(*) AS n_author_str_candidate_opinions,

    COUNT(*) FILTER (
        WHERE gender_resolved
    ) AS n_gender_resolved,

    COUNT(*) FILTER (
        WHERE gender = 'f'
    ) AS n_female_authored,

    COUNT(*) FILTER (
        WHERE gender = 'm'
    ) AS n_male_authored,

    COUNT(*) FILTER (
        WHERE gender_source = 'ambiguous_multiple_genders'
    ) AS n_ambiguous_multiple_genders,

    COUNT(*) FILTER (
        WHERE gender_source = 'no_fjc_match'
    ) AS n_no_fjc_match,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE gender_resolved
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_gender_resolved

FROM ext.author_gender_author_str_fjc
GROUP BY year_filed
ORDER BY year_filed;


-- ------------------------------------------------------------
-- 8. Sample: unique judge matches
-- ------------------------------------------------------------

SELECT
    opinion_id,
    court_id,
    date_filed,
    case_name,
    author_str,
    author_last_name_norm,
    gender,
    gender_source,
    n_candidate_judges,
    candidate_names
FROM ext.author_gender_author_str_fjc
WHERE gender_source = 'author_str_fjc_unique_judge'
ORDER BY date_filed DESC NULLS LAST
LIMIT 30;


-- ------------------------------------------------------------
-- 9. Sample: multiple judges, same gender
-- ------------------------------------------------------------

SELECT
    opinion_id,
    court_id,
    date_filed,
    case_name,
    author_str,
    author_last_name_norm,
    gender,
    gender_source,
    n_candidate_judges,
    candidate_names
FROM ext.author_gender_author_str_fjc
WHERE gender_source = 'author_str_fjc_multiple_judges_same_gender'
ORDER BY n_candidate_judges DESC, date_filed DESC NULLS LAST
LIMIT 30;


-- ------------------------------------------------------------
-- 10. Sample: ambiguous multiple genders
-- ------------------------------------------------------------

SELECT
    opinion_id,
    court_id,
    date_filed,
    case_name,
    author_str,
    author_last_name_norm,
    gender,
    gender_source,
    n_candidate_judges,
    n_candidate_genders,
    candidate_names
FROM ext.author_gender_author_str_fjc
WHERE gender_source = 'ambiguous_multiple_genders'
ORDER BY n_candidate_judges DESC, date_filed DESC NULLS LAST
LIMIT 30;


-- ------------------------------------------------------------
-- 11. Most frequent ambiguous last names
-- ------------------------------------------------------------

SELECT
    court_id,
    court_short_name,
    author_last_name_norm,
    COUNT(*) AS n_opinions,
    MAX(n_candidate_judges) AS max_candidate_judges,
    MAX(candidate_names) AS candidate_names
FROM ext.author_gender_author_str_fjc
WHERE gender_source = 'ambiguous_multiple_genders'
GROUP BY
    court_id,
    court_short_name,
    author_last_name_norm
ORDER BY n_opinions DESC
LIMIT 50;


-- ------------------------------------------------------------
-- 12. Most frequent no-FJC-match author_str values
-- ------------------------------------------------------------

SELECT
    court_id,
    court_short_name,
    author_str,
    author_last_name_norm,
    COUNT(*) AS n_opinions
FROM ext.author_gender_author_str_fjc
WHERE gender_source = 'no_fjc_match'
GROUP BY
    court_id,
    court_short_name,
    author_str,
    author_last_name_norm
ORDER BY n_opinions DESC
LIMIT 50;


-- ------------------------------------------------------------
-- 13. Check that author_str-FJC table does not overlap with
--     structured author_id table.
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_author_str_rows,
    COUNT(agid.opinion_id) AS n_overlapping_author_id_rows
FROM ext.author_gender_author_str_fjc ags
LEFT JOIN ext.author_gender_author_id agid
    ON ags.opinion_id = agid.opinion_id;


-- ------------------------------------------------------------
-- 14. Combined potential coverage after author_id + author_str
-- ------------------------------------------------------------

SELECT
    (SELECT COUNT(*) FROM ext.federal_appeal_opinions) AS n_total_federal_appeal_opinions,

    (SELECT COUNT(*) FROM ext.author_gender_author_id) AS n_author_id_rows,

    (SELECT COUNT(*)
     FROM ext.author_gender_author_id
     WHERE gender_resolved
    ) AS n_author_id_gender_resolved,

    (SELECT COUNT(*)
     FROM ext.author_gender_author_str_fjc
    ) AS n_author_str_candidate_rows,

    (SELECT COUNT(*)
     FROM ext.author_gender_author_str_fjc
     WHERE gender_resolved
    ) AS n_author_str_fjc_gender_resolved,

    (
        (SELECT COUNT(*)
         FROM ext.author_gender_author_id
         WHERE gender_resolved)
        +
        (SELECT COUNT(*)
         FROM ext.author_gender_author_str_fjc
         WHERE gender_resolved)
    ) AS n_total_gender_resolved_before_final_merge,

    ROUND(
        100.0 * (
            (SELECT COUNT(*)
             FROM ext.author_gender_author_id
             WHERE gender_resolved)
            +
            (SELECT COUNT(*)
             FROM ext.author_gender_author_str_fjc
             WHERE gender_resolved)
        ) / NULLIF(
            (SELECT COUNT(*) FROM ext.federal_appeal_opinions),
            0
        ),
        2
    ) AS pct_total_gender_resolved_before_final_merge;