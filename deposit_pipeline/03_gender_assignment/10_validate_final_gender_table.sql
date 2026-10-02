-- ============================================================
-- 10_validate_final_gender_table.sql
--
-- Purpose:
--   Final validation of gender coverage across all four
--   resolution steps.
--
-- Input:
--   ext.author_gender_final_with_html
--   ext.federal_appeal_opinions
--
-- Prerequisite:
--   09_create_final_gender_table.sql
-- ============================================================

\pset pager off
\timing on


-- ------------------------------------------------------------
-- 1. Overall gender coverage
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_total_opinions,

    COUNT(*) FILTER (
        WHERE agf.gender_resolved
    ) AS n_gender_resolved,

    COUNT(*) FILTER (
        WHERE NOT agf.gender_resolved
    ) AS n_gender_unresolved,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE agf.gender_resolved
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_gender_resolved,

    COUNT(*) FILTER (WHERE agf.gender = 'f') AS n_female_authored,
    COUNT(*) FILTER (WHERE agf.gender = 'm') AS n_male_authored,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE agf.gender = 'f')
        / NULLIF(COUNT(*) FILTER (WHERE agf.gender_resolved), 0),
        2
    ) AS pct_female_among_resolved,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE agf.gender = 'm')
        / NULLIF(COUNT(*) FILTER (WHERE agf.gender_resolved), 0),
        2
    ) AS pct_male_among_resolved

FROM ext.author_gender_final_with_html agf;


-- ------------------------------------------------------------
-- 2. Coverage by assignment channel (which step resolved it)
-- ------------------------------------------------------------

SELECT
    agf.final_gender_assignment_channel,
    agf.final_gender_assignment_priority,

    COUNT(*) AS n_opinions,

    COUNT(*) FILTER (WHERE agf.gender = 'f') AS n_female,
    COUNT(*) FILTER (WHERE agf.gender = 'm') AS n_male,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE agf.gender = 'f')
        / NULLIF(COUNT(*) FILTER (WHERE agf.gender_resolved), 0),
        2
    ) AS pct_female_among_resolved

FROM ext.author_gender_final_with_html agf
GROUP BY 1, 2
ORDER BY 2;


-- ------------------------------------------------------------
-- 3. Coverage by opinion_type and precedential_status
-- ------------------------------------------------------------

SELECT
    agf.opinion_type,
    agf.precedential_status,

    COUNT(*) AS n_total,

    COUNT(*) FILTER (WHERE agf.gender_resolved) AS n_resolved,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE agf.gender_resolved)
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_resolved,

    COUNT(*) FILTER (WHERE agf.gender = 'f') AS n_female,
    COUNT(*) FILTER (WHERE agf.gender = 'm') AS n_male

FROM ext.author_gender_final_with_html agf
GROUP BY 1, 2
ORDER BY n_total DESC;


-- ------------------------------------------------------------
-- 4. Coverage by court
-- ------------------------------------------------------------

SELECT
    agf.court_id,
    agf.court_short_name,

    COUNT(*) AS n_total_opinions,

    COUNT(*) FILTER (WHERE agf.gender_resolved)     AS n_gender_resolved,
    COUNT(*) FILTER (WHERE NOT agf.gender_resolved) AS n_gender_unresolved,
    COUNT(*) FILTER (WHERE agf.gender = 'f')        AS n_female_authored,
    COUNT(*) FILTER (WHERE agf.gender = 'm')        AS n_male_authored,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE agf.gender_resolved)
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_gender_resolved,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE agf.gender = 'f')
        / NULLIF(COUNT(*) FILTER (WHERE agf.gender_resolved), 0),
        2
    ) AS pct_female_among_resolved

FROM ext.author_gender_final_with_html agf
GROUP BY agf.court_id, agf.court_short_name
ORDER BY agf.court_id;


-- ------------------------------------------------------------
-- 5. Coverage by year
-- ------------------------------------------------------------

SELECT
    agf.year_filed,

    COUNT(*) AS n_total_opinions,

    COUNT(*) FILTER (WHERE agf.gender_resolved)     AS n_gender_resolved,
    COUNT(*) FILTER (WHERE NOT agf.gender_resolved) AS n_gender_unresolved,
    COUNT(*) FILTER (WHERE agf.gender = 'f')        AS n_female_authored,
    COUNT(*) FILTER (WHERE agf.gender = 'm')        AS n_male_authored,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE agf.gender_resolved)
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_gender_resolved,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE agf.gender = 'f')
        / NULLIF(COUNT(*) FILTER (WHERE agf.gender_resolved), 0),
        2
    ) AS pct_female_among_resolved

FROM ext.author_gender_final_with_html agf
GROUP BY agf.year_filed
ORDER BY agf.year_filed;


-- ------------------------------------------------------------
-- 6. HTML extraction results specifically
--    by HTML layout and extraction pattern
-- ------------------------------------------------------------

SELECT
    agf.html_html_type,
    agf.html_extraction_pattern,
    agf.html_gender_source,

    COUNT(*) AS n_opinions,
    COUNT(*) FILTER (WHERE agf.html_gender_resolved) AS n_html_resolved,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE agf.html_gender_resolved)
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_html_resolved,

    COUNT(*) FILTER (WHERE agf.html_gender = 'f') AS n_female,
    COUNT(*) FILTER (WHERE agf.html_gender = 'm') AS n_male

FROM ext.author_gender_final_with_html agf
WHERE agf.html_gender_source IS NOT NULL
GROUP BY 1, 2, 3
ORDER BY agf.html_html_type, agf.html_extraction_pattern, n_opinions DESC;


-- ------------------------------------------------------------
-- 6b. HTML extraction artifact check
--     should return zero rows
-- ------------------------------------------------------------

SELECT
    agf.opinion_id,
    agf.court_id,
    agf.year_filed,
    agf.final_gender_assignment_channel,
    agf.html_html_type,
    agf.html_extraction_pattern,
    agf.html_extracted_author_name,
    agf.html_candidate_names,
    agf.gender
FROM ext.author_gender_final_with_html agf
WHERE agf.html_extracted_author_name ~* '(^|[[:space:]])and[[:space:]]'
   OR agf.html_extracted_author_name ~* ';'
LIMIT 100;


-- ------------------------------------------------------------
-- 6c. HTML extraction patterns that actually determined final gender
-- ------------------------------------------------------------

SELECT
    agf.html_html_type,
    agf.html_extraction_pattern,

    COUNT(*) AS n_final_html_assigned,

    COUNT(*) FILTER (WHERE agf.gender = 'f') AS n_female,
    COUNT(*) FILTER (WHERE agf.gender = 'm') AS n_male,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE agf.gender = 'f')
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_female

FROM ext.author_gender_final_with_html agf
WHERE agf.final_gender_assignment_channel = 'html_extraction'
GROUP BY 1, 2
ORDER BY n_final_html_assigned DESC;


-- ------------------------------------------------------------
-- 7. Remaining unresolved: breakdown by reason
-- ------------------------------------------------------------

SELECT
    agf.gender_source,
    agf.opinion_type,
    agf.precedential_status,

    COUNT(*) AS n_unresolved

FROM ext.author_gender_final_with_html agf
WHERE agf.gender_resolved = FALSE
GROUP BY 1, 2, 3
ORDER BY n_unresolved DESC
LIMIT 30;


-- ------------------------------------------------------------
-- 8. Nature of suit availability
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_total_opinions,

    COUNT(*) FILTER (
        WHERE fao.cluster_nature_of_suit IS NOT NULL
          AND TRIM(fao.cluster_nature_of_suit) <> ''
    ) AS n_with_cluster_nature_of_suit,

    COUNT(*) FILTER (
        WHERE fao.docket_nature_of_suit IS NOT NULL
          AND TRIM(fao.docket_nature_of_suit) <> ''
    ) AS n_with_docket_nature_of_suit,

    COUNT(*) FILTER (
        WHERE COALESCE(
            NULLIF(TRIM(fao.cluster_nature_of_suit), ''),
            NULLIF(TRIM(fao.docket_nature_of_suit), '')
        ) IS NOT NULL
    ) AS n_with_any_nature_of_suit,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE COALESCE(
                NULLIF(TRIM(fao.cluster_nature_of_suit), ''),
                NULLIF(TRIM(fao.docket_nature_of_suit), '')
            ) IS NOT NULL
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_with_any_nature_of_suit

FROM ext.author_gender_final_with_html agf
JOIN ext.federal_appeal_opinions fao
    ON agf.opinion_id = fao.opinion_id;


-- ------------------------------------------------------------
-- 9. Nature of suit among gender-resolved opinions
-- ------------------------------------------------------------

WITH base AS (
    SELECT
        agf.gender,
        agf.gender_resolved,
        COALESCE(
            NULLIF(TRIM(fao.cluster_nature_of_suit), ''),
            NULLIF(TRIM(fao.docket_nature_of_suit), ''),
            'missing'
        ) AS nature_of_suit
    FROM ext.author_gender_final_with_html agf
    JOIN ext.federal_appeal_opinions fao
        ON agf.opinion_id = fao.opinion_id
    WHERE agf.gender_resolved
)

SELECT
    nature_of_suit,

    COUNT(*) AS n_gender_resolved_opinions,

    COUNT(*) FILTER (WHERE gender = 'f') AS n_female_authored,
    COUNT(*) FILTER (WHERE gender = 'm') AS n_male_authored,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE gender = 'f')
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_female,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE gender = 'm')
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_male

FROM base
GROUP BY nature_of_suit
ORDER BY n_gender_resolved_opinions DESC
LIMIT 100;


-- ------------------------------------------------------------
-- 10. Nature of suit by court (gender-resolved only)
-- ------------------------------------------------------------

WITH base AS (
    SELECT
        agf.gender,
        agf.gender_resolved,
        fao.court_id,
        fao.court_short_name,
        COALESCE(
            NULLIF(TRIM(fao.cluster_nature_of_suit), ''),
            NULLIF(TRIM(fao.docket_nature_of_suit), ''),
            'missing'
        ) AS nature_of_suit
    FROM ext.author_gender_final_with_html agf
    JOIN ext.federal_appeal_opinions fao
        ON agf.opinion_id = fao.opinion_id
)

SELECT
    court_id,
    court_short_name,
    nature_of_suit,

    COUNT(*) AS n_total_opinions,

    COUNT(*) FILTER (WHERE gender_resolved) AS n_gender_resolved,
    COUNT(*) FILTER (WHERE gender = 'f')    AS n_female_authored,
    COUNT(*) FILTER (WHERE gender = 'm')    AS n_male_authored,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE gender = 'f')
        / NULLIF(COUNT(*) FILTER (WHERE gender_resolved), 0),
        2
    ) AS pct_female_among_resolved,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE gender_resolved)
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_gender_resolved

FROM base
GROUP BY court_id, court_short_name, nature_of_suit
ORDER BY court_id, n_total_opinions DESC
LIMIT 300;

-- ------------------------------------------------------------
-- 7b. Unresolved: breakdown by year range
-- ------------------------------------------------------------

SELECT
    CASE
        WHEN year_filed < 1960 THEN 'before 1960'
        WHEN year_filed BETWEEN 1960 AND 1979 THEN '1960-1979'
        WHEN year_filed BETWEEN 1980 AND 1999 THEN '1980-1999'
        WHEN year_filed BETWEEN 2000 AND 2019 THEN '2000-2019'
        WHEN year_filed >= 2020 THEN '2020+'
        ELSE 'unknown'
    END AS year_range,
    COUNT(*) AS n_unresolved,
    ROUND(100.0 * COUNT(*) / NULLIF(
        (SELECT COUNT(*) FROM ext.author_gender_final_with_html
         WHERE NOT gender_resolved), 0), 2) AS pct_of_unresolved
FROM ext.author_gender_final_with_html
WHERE NOT gender_resolved
GROUP BY 1
ORDER BY 1;


-- ------------------------------------------------------------
-- 7c. Unresolved: no author_id AND no author_str
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS n_no_author_info,
    ROUND(100.0 * COUNT(*) / NULLIF(
        (SELECT COUNT(*) FROM ext.author_gender_final_with_html
         WHERE NOT gender_resolved), 0), 2) AS pct_of_unresolved
FROM ext.author_gender_final_with_html
WHERE NOT gender_resolved
  AND author_id IS NULL
  AND (author_str IS NULL OR BTRIM(author_str) = '');

-- ------------------------------------------------------------
-- 7c. Unresolved: no xml author tag AND no html
-- ------------------------------------------------------------

SELECT
    CASE WHEN o.xml_harvard IS NOT NULL
              AND o.xml_harvard ILIKE '%<author%'
         THEN 'has_xml_author_tag'
         ELSE 'no_xml_author_tag' END AS xml_status,
    CASE WHEN o.html_with_citations IS NOT NULL
              AND BTRIM(o.html_with_citations) <> ''
         THEN 'has_html'
         ELSE 'no_html' END AS html_status,
    COUNT(*) AS n
FROM ext.author_gender_final_with_html agf
JOIN public.search_opinion o ON o.id = agf.opinion_id
WHERE agf.gender_resolved = FALSE
  AND agf.author_id IS NULL
  AND (agf.author_str IS NULL OR BTRIM(agf.author_str) = '')
GROUP BY 1, 2
ORDER BY n DESC;

-- ------------------------------------------------------------
-- 11. Fixed-snapshot regression assertion
-- ------------------------------------------------------------
-- These are the publication-release values for the fixed 2026-03-31
-- snapshot.  They retain all 555,296 thesis assignments and add the single
-- documented correction for opinion 2966699.  Fail loudly instead of
-- allowing an unreviewed extraction change into the release.

DO $$
DECLARE
    n_total      bigint;
    n_resolved   bigint;
    n_female     bigint;
    n_male       bigint;
BEGIN
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE gender_resolved),
        COUNT(*) FILTER (WHERE gender = 'f'),
        COUNT(*) FILTER (WHERE gender = 'm')
    INTO n_total, n_resolved, n_female, n_male
    FROM ext.author_gender_final_with_html;

    IF (n_total, n_resolved, n_female, n_male)
       IS DISTINCT FROM (1472533::bigint, 555297::bigint,
                         69936::bigint, 485361::bigint)
    THEN
        RAISE EXCEPTION
            'Release regression failed: total=%, resolved=%, female=%, male=%; expected 1472533, 555297, 69936, 485361',
            n_total, n_resolved, n_female, n_male;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM ext.author_gender_final_with_html
        WHERE opinion_id = 2966699
          AND gender = 'm'
          AND gender_resolved
          AND final_gender_assignment_channel = 'html_extraction'
          AND html_extraction_pattern = 'A3_circuit_judge_line_pre_inline'
          AND html_extracted_author_name = 'LUTTIG'
    ) THEN
        RAISE EXCEPTION
            'Documented release correction for opinion 2966699 is missing';
    END IF;
END
$$;
