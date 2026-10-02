-- ============================================================
-- 07_validate_steps1_2_combined.sql
--
-- Purpose:
--   Validate the combined Steps 1+2 author-gender table.
--
-- Input:
--   ext.author_gender_final
--
-- Prerequisite:
--   06_create_steps1_2_combined.sql
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
  AND table_name = 'author_gender_final';


-- ------------------------------------------------------------
-- 2. Row count: should equal ext.federal_appeal_opinions
-- ------------------------------------------------------------

SELECT
    (SELECT COUNT(*) FROM ext.federal_appeal_opinions) AS n_federal_appeal_opinions,
    (SELECT COUNT(*) FROM ext.author_gender_final) AS n_author_gender_final_rows,
    (
        (SELECT COUNT(*) FROM ext.federal_appeal_opinions)
        -
        (SELECT COUNT(*) FROM ext.author_gender_final)
    ) AS row_count_difference;


-- ------------------------------------------------------------
-- 3. Primary-key check: duplicate opinion_id should be zero
-- ------------------------------------------------------------

SELECT
    opinion_id,
    COUNT(*) AS n_rows
FROM ext.author_gender_final
GROUP BY opinion_id
HAVING COUNT(*) > 1
ORDER BY n_rows DESC, opinion_id
LIMIT 30;


-- ------------------------------------------------------------
-- 4. Join-back check to Federal-Appeals opinions
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_final_rows,
    COUNT(fao.opinion_id) AS n_joined_to_federal_appeal_opinions,
    COUNT(*) - COUNT(fao.opinion_id) AS n_missing_in_federal_appeal_opinions
FROM ext.author_gender_final agf
LEFT JOIN ext.federal_appeal_opinions fao
    ON agf.opinion_id = fao.opinion_id;


-- ------------------------------------------------------------
-- 5. Overall gender coverage
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_total_opinions,

    COUNT(*) FILTER (
        WHERE gender_resolved
    ) AS n_gender_resolved,

    COUNT(*) FILTER (
        WHERE NOT gender_resolved
    ) AS n_gender_unresolved,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE gender_resolved
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_gender_resolved,

    COUNT(*) FILTER (
        WHERE gender = 'f'
    ) AS n_female_authored,

    COUNT(*) FILTER (
        WHERE gender = 'm'
    ) AS n_male_authored,

    COUNT(*) FILTER (
        WHERE gender IS NULL
    ) AS n_gender_null

FROM ext.author_gender_final;


-- ------------------------------------------------------------
-- 6. Gender distribution among resolved opinions
-- ------------------------------------------------------------

SELECT
    gender,
    COUNT(*) AS n_opinions,
    ROUND(
        100.0 * COUNT(*) / NULLIF(
            (
                SELECT COUNT(*)
                FROM ext.author_gender_final
                WHERE gender_resolved
            ),
            0
        ),
        2
    ) AS pct_of_resolved
FROM ext.author_gender_final
WHERE gender_resolved
GROUP BY gender
ORDER BY gender;


-- ------------------------------------------------------------
-- 7. Distribution by gender_source
-- ------------------------------------------------------------

SELECT
    gender_source,
    gender_resolved,
    COUNT(*) AS n_opinions,
    ROUND(
        100.0 * COUNT(*) / NULLIF(
            (SELECT COUNT(*) FROM ext.author_gender_final),
            0
        ),
        2
    ) AS pct_of_total
FROM ext.author_gender_final
GROUP BY gender_source, gender_resolved
ORDER BY n_opinions DESC;


-- ------------------------------------------------------------
-- 8. Distribution by match-quality tier
-- ------------------------------------------------------------

SELECT
    gender_match_quality_tier,
    gender_match_quality_label,
    gender_resolved,
    COUNT(*) AS n_opinions,
    ROUND(
        100.0 * COUNT(*) / NULLIF(
            (SELECT COUNT(*) FROM ext.author_gender_final),
            0
        ),
        2
    ) AS pct_of_total
FROM ext.author_gender_final
GROUP BY
    gender_match_quality_tier,
    gender_match_quality_label,
    gender_resolved
ORDER BY
    gender_match_quality_tier,
    n_opinions DESC;


-- ------------------------------------------------------------
-- 9. Court-level coverage
-- ------------------------------------------------------------

SELECT
    court_id,
    court_short_name,
    COUNT(*) AS n_total_opinions,

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
        WHERE gender_source = 'author_id'
    ) AS n_author_id_resolved,

    COUNT(*) FILTER (
        WHERE gender_source = 'author_str_fjc_unique_judge'
    ) AS n_author_str_unique_judge,

    COUNT(*) FILTER (
        WHERE gender_source = 'author_str_fjc_suffix_unique_gender'
    ) AS n_author_str_suffix_unique_gender,

    COUNT(*) FILTER (
        WHERE gender_source = 'author_str_fjc_multiple_judges_same_gender'
    ) AS n_author_str_multiple_same_gender,

    COUNT(*) FILTER (
        WHERE gender_source = 'ambiguous_multiple_genders'
    ) AS n_ambiguous_multiple_genders,

    COUNT(*) FILTER (
        WHERE gender_source = 'no_fjc_match'
    ) AS n_no_fjc_match,

    COUNT(*) FILTER (
        WHERE gender_source = 'no_author_id_or_author_str'
    ) AS n_no_author_id_or_author_str,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE gender_resolved
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_gender_resolved

FROM ext.author_gender_final
GROUP BY court_id, court_short_name
ORDER BY court_id;


-- ------------------------------------------------------------
-- 10. Year-level coverage
-- ------------------------------------------------------------

SELECT
    year_filed,
    COUNT(*) AS n_total_opinions,

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
        WHERE gender_source = 'author_id'
    ) AS n_author_id_resolved,

    COUNT(*) FILTER (
        WHERE gender_source IN (
            'author_str_fjc_unique_judge',
            'author_str_fjc_suffix_unique_gender',
            'author_str_fjc_multiple_judges_same_gender'
        )
    ) AS n_author_str_fjc_resolved,

    COUNT(*) FILTER (
        WHERE gender_source = 'ambiguous_multiple_genders'
    ) AS n_ambiguous_multiple_genders,

    COUNT(*) FILTER (
        WHERE gender_source = 'no_fjc_match'
    ) AS n_no_fjc_match,

    COUNT(*) FILTER (
        WHERE gender_source = 'no_author_id_or_author_str'
    ) AS n_no_author_id_or_author_str,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE gender_resolved
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_gender_resolved

FROM ext.author_gender_final
GROUP BY year_filed
ORDER BY year_filed;


-- ------------------------------------------------------------
-- 11. Check consistency: author_id source should correspond to
--     ext.author_gender_author_id
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_final_author_id_rows,
    COUNT(agid.opinion_id) AS n_joined_to_author_id_table,
    COUNT(*) - COUNT(agid.opinion_id) AS n_missing_in_author_id_table
FROM ext.author_gender_final agf
LEFT JOIN ext.author_gender_author_id agid
    ON agf.opinion_id = agid.opinion_id
WHERE agf.gender_source = 'author_id';


-- ------------------------------------------------------------
-- 12. Check consistency: author_str-FJC resolved sources should
--     correspond to ext.author_gender_author_str_fjc
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_final_author_str_fjc_rows,
    COUNT(ags.opinion_id) AS n_joined_to_author_str_fjc_table,
    COUNT(*) - COUNT(ags.opinion_id) AS n_missing_in_author_str_fjc_table
FROM ext.author_gender_final agf
LEFT JOIN ext.author_gender_author_str_fjc ags
    ON agf.opinion_id = ags.opinion_id
WHERE agf.gender_source IN (
    'author_str_fjc_unique_judge',
    'author_str_fjc_suffix_unique_gender',
    'author_str_fjc_multiple_judges_same_gender',
    'ambiguous_multiple_genders',
    'ambiguous_suffix_multiple_genders',
    'no_fjc_match'
);


-- ------------------------------------------------------------
-- 13. Check impossible states
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_gender_resolved_but_gender_null
FROM ext.author_gender_final
WHERE gender_resolved
  AND gender IS NULL;

SELECT
    COUNT(*) AS n_gender_not_resolved_but_gender_present
FROM ext.author_gender_final
WHERE NOT gender_resolved
  AND gender IS NOT NULL;

SELECT
    COUNT(*) AS n_invalid_gender_values
FROM ext.author_gender_final
WHERE gender IS NOT NULL
  AND gender NOT IN ('m', 'f');


-- ------------------------------------------------------------
-- 14. Sample resolved female-authored opinions
-- ------------------------------------------------------------

SELECT
    opinion_id,
    court_id,
    date_filed,
    case_name,
    author_id,
    author_str,
    gender,
    gender_source,
    gender_match_quality_tier,
    candidate_names
FROM ext.author_gender_final
WHERE gender = 'f'
ORDER BY date_filed DESC NULLS LAST
LIMIT 30;


-- ------------------------------------------------------------
-- 15. Sample resolved male-authored opinions
-- ------------------------------------------------------------

SELECT
    opinion_id,
    court_id,
    date_filed,
    case_name,
    author_id,
    author_str,
    gender,
    gender_source,
    gender_match_quality_tier,
    candidate_names
FROM ext.author_gender_final
WHERE gender = 'm'
ORDER BY date_filed DESC NULLS LAST
LIMIT 30;


-- ------------------------------------------------------------
-- 16. Sample unresolved opinions with author_str
-- ------------------------------------------------------------

SELECT
    opinion_id,
    court_id,
    date_filed,
    case_name,
    author_id,
    author_str,
    gender_source,
    gender_match_quality_tier,
    author_last_name_norm,
    n_candidate_judges,
    n_candidate_genders,
    candidate_names
FROM ext.author_gender_final
WHERE NOT gender_resolved
  AND author_str IS NOT NULL
  AND TRIM(author_str) <> ''
ORDER BY date_filed DESC NULLS LAST
LIMIT 30;


-- ------------------------------------------------------------
-- 17. Sample unresolved opinions without author_id or author_str
-- ------------------------------------------------------------

SELECT
    opinion_id,
    court_id,
    date_filed,
    case_name,
    author_id,
    author_str,
    gender_source,
    gender_match_quality_tier
FROM ext.author_gender_final
WHERE gender_source = 'no_author_id_or_author_str'
ORDER BY date_filed DESC NULLS LAST
LIMIT 30;