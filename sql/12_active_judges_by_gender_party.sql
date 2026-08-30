\o /data/workspace/kmayer/courtlistener/cleaned_csv/active_judges_by_gender_party.csv
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
      COALESCE(g.gender_clean, 'Missing') AS gender_clean,
      CASE
          WHEN COALESCE(pp.political_party_clean, 'Missing') IN ('Democratic', 'Republican') THEN COALESCE(pp.political_party_clean, 'Missing')
          WHEN COALESCE(pp.political_party_clean, 'Missing') IN ('Missing', 'Multiple', 'Other') THEN COALESCE(pp.political_party_clean, 'Missing')
          ELSE 'Other'
      END AS political_party_group,
      COUNT(DISTINCT a.person_id) AS n_active_judges
  FROM active_judges a
  LEFT JOIN person_gender g
    ON g.person_id = a.person_id
  LEFT JOIN person_party pp
    ON pp.person_id = a.person_id
  GROUP BY
      COALESCE(g.gender_clean, 'Missing'),
      CASE
          WHEN COALESCE(pp.political_party_clean, 'Missing') IN ('Democratic', 'Republican') THEN COALESCE(pp.political_party_clean, 'Missing')
          WHEN COALESCE(pp.political_party_clean, 'Missing') IN ('Missing', 'Multiple', 'Other') THEN COALESCE(pp.political_party_clean, 'Missing')
          ELSE 'Other'
      END
  ORDER BY political_party_group, gender_clean
) TO STDOUT WITH CSV HEADER;
\o