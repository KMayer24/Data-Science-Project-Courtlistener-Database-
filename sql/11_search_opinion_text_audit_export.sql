-- 11_search_opinion_text_audit_export.sql

\o /data/workspace/kmayer/courtlistener/cleaned_csv/search_opinion_text_audit_summary.csv
COPY (
  SELECT *
  FROM (
      SELECT
          'html_with_citations' AS field_name,
          COUNT(*) AS total_rows,
          COUNT(*) FILTER (
              WHERE NULLIF(TRIM(html_with_citations), '') IS NOT NULL
          ) AS non_empty_rows,
          ROUND(
              100.0 * COUNT(*) FILTER (
                  WHERE NULLIF(TRIM(html_with_citations), '') IS NOT NULL
              ) / COUNT(*),
              2
          ) AS non_empty_pct
      FROM public.search_opinion

      UNION ALL

      SELECT
          'xml_harvard' AS field_name,
          COUNT(*) AS total_rows,
          COUNT(*) FILTER (
              WHERE NULLIF(TRIM(xml_harvard), '') IS NOT NULL
          ) AS non_empty_rows,
          ROUND(
              100.0 * COUNT(*) FILTER (
                  WHERE NULLIF(TRIM(xml_harvard), '') IS NOT NULL
              ) / COUNT(*),
              2
          ) AS non_empty_pct
      FROM public.search_opinion

      UNION ALL

      SELECT
          'plain_text' AS field_name,
          COUNT(*) AS total_rows,
          COUNT(*) FILTER (
              WHERE NULLIF(TRIM(plain_text), '') IS NOT NULL
          ) AS non_empty_rows,
          ROUND(
              100.0 * COUNT(*) FILTER (
                  WHERE NULLIF(TRIM(plain_text), '') IS NOT NULL
              ) / COUNT(*),
              2
          ) AS non_empty_pct
      FROM public.search_opinion

      UNION ALL

      SELECT
          'html' AS field_name,
          COUNT(*) AS total_rows,
          COUNT(*) FILTER (
              WHERE NULLIF(TRIM(html), '') IS NOT NULL
          ) AS non_empty_rows,
          ROUND(
              100.0 * COUNT(*) FILTER (
                  WHERE NULLIF(TRIM(html), '') IS NOT NULL
              ) / COUNT(*),
              2
          ) AS non_empty_pct
      FROM public.search_opinion

      UNION ALL

      SELECT
          'author_str' AS field_name,
          COUNT(*) AS total_rows,
          COUNT(*) FILTER (
              WHERE NULLIF(TRIM(author_str), '') IS NOT NULL
          ) AS non_empty_rows,
          ROUND(
              100.0 * COUNT(*) FILTER (
                  WHERE NULLIF(TRIM(author_str), '') IS NOT NULL
              ) / COUNT(*),
              2
          ) AS non_empty_pct
      FROM public.search_opinion

      UNION ALL

      SELECT
          'any_text_available' AS field_name,
          COUNT(*) AS total_rows,
          COUNT(*) FILTER (
              WHERE
                  NULLIF(TRIM(plain_text), '') IS NOT NULL
                  OR NULLIF(TRIM(html), '') IS NOT NULL
                  OR NULLIF(TRIM(html_with_citations), '') IS NOT NULL
                  OR NULLIF(TRIM(xml_harvard), '') IS NOT NULL
          ) AS non_empty_rows,
          ROUND(
              100.0 * COUNT(*) FILTER (
                  WHERE
                      NULLIF(TRIM(plain_text), '') IS NOT NULL
                      OR NULLIF(TRIM(html), '') IS NOT NULL
                      OR NULLIF(TRIM(html_with_citations), '') IS NOT NULL
                      OR NULLIF(TRIM(xml_harvard), '') IS NOT NULL
              ) / COUNT(*),
              2
          ) AS non_empty_pct
      FROM public.search_opinion
  ) s
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/search_opinion_text_audit_examples.csv
COPY (
  SELECT
      id,
      type,
      LEFT(author_str, 100) AS author_preview,
      LEFT(plain_text, 300) AS plain_text_preview,
      LEFT(html, 300) AS html_preview,
      LEFT(html_with_citations, 300) AS html_with_citations_preview,
      LEFT(xml_harvard, 300) AS xml_harvard_preview
  FROM public.search_opinion
  WHERE
      NULLIF(TRIM(html_with_citations), '') IS NOT NULL
      OR NULLIF(TRIM(xml_harvard), '') IS NOT NULL
      OR NULLIF(TRIM(plain_text), '') IS NOT NULL
      OR NULLIF(TRIM(html), '') IS NOT NULL
  LIMIT 500
) TO STDOUT WITH CSV HEADER;
\o