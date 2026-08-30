\o /data/workspace/kmayer/courtlistener/cleaned_csv/active_judges_female_share_by_party.csv
COPY (
  WITH active_judges AS (
      SELECT DISTINCT person_id
      FROM public.people_db_position
      WHERE person_id IS NOT NULL
        AND date_termination IS NULL
        AND date_retirement IS NULL
  ),
  person_gender AS (
      SELECT
          p.id AS person_id,
          CASE
              WHEN p.gender IS NULL OR TRIM(p.gender) = '' THEN 'Missing'
              WHEN LOWER(TRIM(p.gender)) = 'm' THEN 'Male'
              WHEN LOWER(TRIM(p.gender)) = 'f' THEN 'Female'
              ELSE 'Other'
          END AS gender_clean
      FROM public.people_db_person p
  ),
  person_party AS (
      SELECT
          pa.person_id,
          CASE
              WHEN COUNT(DISTINCT NULLIF(TRIM(pa.political_party), '')) = 0 THEN 'Missing'
              WHEN COUNT(DISTINCT NULLIF(TRIM(pa.political_party), '')) = 1 THEN
                  CASE
                      WHEN MIN(NULLIF(TRIM(pa.political_party), '')) = 'd' THEN 'Democratic'
                      WHEN MIN(NULLIF(TRIM(pa.political_party), '')) = 'r' THEN 'Republican'
                      ELSE 'Other'
                  END
              ELSE 'Multiple'
          END AS political_party_clean
      FROM public.people_db_politicalaffiliation pa
      WHERE pa.person_id IS NOT NULL
      GROUP BY pa.person_id
  )
  SELECT
      pp.political_party_clean AS political_party_group,
      COUNT(DISTINCT a.person_id) AS total_active_judges,
      COUNT(DISTINCT CASE WHEN g.gender_clean = 'Female' THEN a.person_id END) AS female_active_judges,
      ROUND(
          100.0 * COUNT(DISTINCT CASE WHEN g.gender_clean = 'Female' THEN a.person_id END)
          / COUNT(DISTINCT a.person_id),
          1
      ) AS female_share_pct
  FROM active_judges a
  LEFT JOIN person_gender g
    ON g.person_id = a.person_id
  LEFT JOIN person_party pp
    ON pp.person_id = a.person_id
  WHERE pp.political_party_clean IN ('Democratic', 'Republican')
  GROUP BY pp.political_party_clean
  ORDER BY pp.political_party_clean
) TO STDOUT WITH CSV HEADER;
\o