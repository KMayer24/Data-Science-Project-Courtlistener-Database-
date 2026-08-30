-- 11_search_opinion_text_audit.sql

-- 1. Coverage: field is non-empty
SELECT *
FROM (
    SELECT 'plain_text' AS field_name,
           COUNT(*) AS total_rows,
           COUNT(*) FILTER (WHERE plain_text IS NOT NULL AND TRIM(plain_text) <> '') AS non_empty_rows,
           ROUND(
               100.0 * COUNT(*) FILTER (WHERE plain_text IS NOT NULL AND TRIM(plain_text) <> '') / COUNT(*),
               2
           ) AS non_empty_pct
    FROM public.search_opinion

    UNION ALL
    SELECT 'html',
           COUNT(*),
           COUNT(*) FILTER (WHERE html IS NOT NULL AND TRIM(html) <> ''),
           ROUND(100.0 * COUNT(*) FILTER (WHERE html IS NOT NULL AND TRIM(html) <> '') / COUNT(*), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'html_lawbox',
           COUNT(*),
           COUNT(*) FILTER (WHERE html_lawbox IS NOT NULL AND TRIM(html_lawbox) <> ''),
           ROUND(100.0 * COUNT(*) FILTER (WHERE html_lawbox IS NOT NULL AND TRIM(html_lawbox) <> '') / COUNT(*), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'html_columbia',
           COUNT(*),
           COUNT(*) FILTER (WHERE html_columbia IS NOT NULL AND TRIM(html_columbia) <> ''),
           ROUND(100.0 * COUNT(*) FILTER (WHERE html_columbia IS NOT NULL AND TRIM(html_columbia) <> '') / COUNT(*), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'html_anon_2020',
           COUNT(*),
           COUNT(*) FILTER (WHERE html_anon_2020 IS NOT NULL AND TRIM(html_anon_2020) <> ''),
           ROUND(100.0 * COUNT(*) FILTER (WHERE html_anon_2020 IS NOT NULL AND TRIM(html_anon_2020) <> '') / COUNT(*), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'xml_harvard',
           COUNT(*),
           COUNT(*) FILTER (WHERE xml_harvard IS NOT NULL AND TRIM(xml_harvard) <> ''),
           ROUND(100.0 * COUNT(*) FILTER (WHERE xml_harvard IS NOT NULL AND TRIM(xml_harvard) <> '') / COUNT(*), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'xml_scan',
           COUNT(*),
           COUNT(*) FILTER (WHERE xml_scan IS NOT NULL AND TRIM(xml_scan) <> ''),
           ROUND(100.0 * COUNT(*) FILTER (WHERE xml_scan IS NOT NULL AND TRIM(xml_scan) <> '') / COUNT(*), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'html_with_citations',
           COUNT(*),
           COUNT(*) FILTER (WHERE html_with_citations IS NOT NULL AND TRIM(html_with_citations) <> ''),
           ROUND(100.0 * COUNT(*) FILTER (WHERE html_with_citations IS NOT NULL AND TRIM(html_with_citations) <> '') / COUNT(*), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'author_str',
           COUNT(*),
           COUNT(*) FILTER (WHERE author_str IS NOT NULL AND TRIM(author_str) <> ''),
           ROUND(100.0 * COUNT(*) FILTER (WHERE author_str IS NOT NULL AND TRIM(author_str) <> '') / COUNT(*), 2)
    FROM public.search_opinion
) t
ORDER BY non_empty_pct DESC;


-- 2. Average length among non-empty entries
SELECT *
FROM (
    SELECT 'plain_text' AS field_name,
           ROUND(AVG(LENGTH(plain_text)) FILTER (WHERE plain_text IS NOT NULL AND TRIM(plain_text) <> ''), 2) AS avg_length_non_empty
    FROM public.search_opinion

    UNION ALL
    SELECT 'html',
           ROUND(AVG(LENGTH(html)) FILTER (WHERE html IS NOT NULL AND TRIM(html) <> ''), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'html_lawbox',
           ROUND(AVG(LENGTH(html_lawbox)) FILTER (WHERE html_lawbox IS NOT NULL AND TRIM(html_lawbox) <> ''), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'html_columbia',
           ROUND(AVG(LENGTH(html_columbia)) FILTER (WHERE html_columbia IS NOT NULL AND TRIM(html_columbia) <> ''), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'html_anon_2020',
           ROUND(AVG(LENGTH(html_anon_2020)) FILTER (WHERE html_anon_2020 IS NOT NULL AND TRIM(html_anon_2020) <> ''), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'xml_harvard',
           ROUND(AVG(LENGTH(xml_harvard)) FILTER (WHERE xml_harvard IS NOT NULL AND TRIM(xml_harvard) <> ''), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'xml_scan',
           ROUND(AVG(LENGTH(xml_scan)) FILTER (WHERE xml_scan IS NOT NULL AND TRIM(xml_scan) <> ''), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'html_with_citations',
           ROUND(AVG(LENGTH(html_with_citations)) FILTER (WHERE html_with_citations IS NOT NULL AND TRIM(html_with_citations) <> ''), 2)
    FROM public.search_opinion

    UNION ALL
    SELECT 'author_str',
           ROUND(AVG(LENGTH(author_str)) FILTER (WHERE author_str IS NOT NULL AND TRIM(author_str) <> ''), 2)
    FROM public.search_opinion
) t
ORDER BY avg_length_non_empty DESC NULLS LAST;


-- 3. Any text available across all text fields
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE
            COALESCE(NULLIF(TRIM(plain_text), ''), NULL) IS NOT NULL
            OR COALESCE(NULLIF(TRIM(html), ''), NULL) IS NOT NULL
            OR COALESCE(NULLIF(TRIM(html_lawbox), ''), NULL) IS NOT NULL
            OR COALESCE(NULLIF(TRIM(html_columbia), ''), NULL) IS NOT NULL
            OR COALESCE(NULLIF(TRIM(html_anon_2020), ''), NULL) IS NOT NULL
            OR COALESCE(NULLIF(TRIM(xml_harvard), ''), NULL) IS NOT NULL
            OR COALESCE(NULLIF(TRIM(xml_scan), ''), NULL) IS NOT NULL
            OR COALESCE(NULLIF(TRIM(html_with_citations), ''), NULL) IS NOT NULL
    ) AS rows_with_any_text,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE
                COALESCE(NULLIF(TRIM(plain_text), ''), NULL) IS NOT NULL
                OR COALESCE(NULLIF(TRIM(html), ''), NULL) IS NOT NULL
                OR COALESCE(NULLIF(TRIM(html_lawbox), ''), NULL) IS NOT NULL
                OR COALESCE(NULLIF(TRIM(html_columbia), ''), NULL) IS NOT NULL
                OR COALESCE(NULLIF(TRIM(html_anon_2020), ''), NULL) IS NOT NULL
                OR COALESCE(NULLIF(TRIM(xml_harvard), ''), NULL) IS NOT NULL
                OR COALESCE(NULLIF(TRIM(xml_scan), ''), NULL) IS NOT NULL
                OR COALESCE(NULLIF(TRIM(html_with_citations), ''), NULL) IS NOT NULL
        ) / COUNT(*),
        2
    ) AS any_text_pct
FROM public.search_opinion;