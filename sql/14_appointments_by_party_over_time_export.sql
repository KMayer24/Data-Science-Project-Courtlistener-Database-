-- 14_appointments_by_party_over_time_export.sql
-- Export annual judicial appointment counts by political party (Democratic / Republican)
-- Joins: people_db_position (date_start) -> people_db_politicalaffiliation
-- Uses position start date as proxy for appointment year.

\o /data/workspace/kmayer/courtlistener/cleaned_csv/appointments_by_party_over_time.csv
COPY (
  WITH person_party AS (
      SELECT
          person_id,
          CASE
              WHEN COUNT(DISTINCT NULLIF(TRIM(political_party), '')) = 0 THEN 'Missing'
              WHEN COUNT(DISTINCT NULLIF(TRIM(political_party), '')) = 1 THEN
                  CASE MIN(NULLIF(TRIM(political_party), ''))
                      WHEN 'd' THEN 'Democratic'
                      WHEN 'r' THEN 'Republican'
                      ELSE 'Other'
                  END
              ELSE 'Multiple'
          END AS political_party_clean
      FROM public.people_db_politicalaffiliation
      WHERE person_id IS NOT NULL
      GROUP BY person_id
  )
  SELECT
      EXTRACT(YEAR FROM pos.date_start)::int AS year,
      pp.political_party_clean,
      COUNT(DISTINCT pos.person_id) AS n_appointments
  FROM public.people_db_position pos
  JOIN person_party pp
      ON pp.person_id = pos.person_id
  WHERE pos.date_start IS NOT NULL
    AND EXTRACT(YEAR FROM pos.date_start) BETWEEN 1900 AND 2024
    AND pp.political_party_clean IN ('Democratic', 'Republican')
  GROUP BY year, pp.political_party_clean
  ORDER BY year, pp.political_party_clean
) TO STDOUT WITH CSV HEADER;
\o
