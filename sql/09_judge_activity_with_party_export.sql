-- 09_judge_activity_with_party_export.sql
-- Export top judge activity tables enriched with political party

\o /data/workspace/kmayer/courtlistener/cleaned_csv/top25_judges_by_authored_opinions_with_party.csv
COPY (
  WITH person_party AS (
      SELECT
          person_id,
          CASE
              WHEN COUNT(DISTINCT NULLIF(TRIM(political_party), '')) = 0 THEN 'Missing'
              WHEN COUNT(DISTINCT NULLIF(TRIM(political_party), '')) = 1 THEN MIN(NULLIF(TRIM(political_party), ''))
              ELSE 'Multiple'
          END AS political_party_clean
      FROM public.people_db_politicalaffiliation
      WHERE person_id IS NOT NULL
      GROUP BY person_id
  )
  SELECT
      p.id AS person_id,
      CONCAT_WS(' ', p.name_first, p.name_middle, p.name_last, p.name_suffix) AS full_name,
      COUNT(o.id) AS authored_opinion_count,
      COALESCE(pp.political_party_clean, 'Missing') AS political_party_clean
  FROM public.people_db_person p
  JOIN public.search_opinion o
    ON o.author_id = p.id
  LEFT JOIN person_party pp
    ON pp.person_id = p.id
  GROUP BY p.id, p.name_first, p.name_middle, p.name_last, p.name_suffix, pp.political_party_clean
  ORDER BY authored_opinion_count DESC
  LIMIT 25
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/top25_judges_by_panel_participation_with_party.csv
COPY (
  WITH person_party AS (
      SELECT
          person_id,
          CASE
              WHEN COUNT(DISTINCT NULLIF(TRIM(political_party), '')) = 0 THEN 'Missing'
              WHEN COUNT(DISTINCT NULLIF(TRIM(political_party), '')) = 1 THEN MIN(NULLIF(TRIM(political_party), ''))
              ELSE 'Multiple'
          END AS political_party_clean
      FROM public.people_db_politicalaffiliation
      WHERE person_id IS NOT NULL
      GROUP BY person_id
  )
  SELECT
      p.id AS person_id,
      CONCAT_WS(' ', p.name_first, p.name_middle, p.name_last, p.name_suffix) AS full_name,
      COUNT(ppanel.id) AS panel_participation_count,
      COALESCE(pp.political_party_clean, 'Missing') AS political_party_clean
  FROM public.people_db_person p
  JOIN public.search_opinioncluster_panel ppanel
    ON ppanel.person_id = p.id
  LEFT JOIN person_party pp
    ON pp.person_id = p.id
  GROUP BY p.id, p.name_first, p.name_middle, p.name_last, p.name_suffix, pp.political_party_clean
  ORDER BY panel_participation_count DESC
  LIMIT 25
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/top25_judges_by_joined_opinions_with_party.csv
COPY (
  WITH person_party AS (
      SELECT
          person_id,
          CASE
              WHEN COUNT(DISTINCT NULLIF(TRIM(political_party), '')) = 0 THEN 'Missing'
              WHEN COUNT(DISTINCT NULLIF(TRIM(political_party), '')) = 1 THEN MIN(NULLIF(TRIM(political_party), ''))
              ELSE 'Multiple'
          END AS political_party_clean
      FROM public.people_db_politicalaffiliation
      WHERE person_id IS NOT NULL
      GROUP BY person_id
  )
  SELECT
      p.id AS person_id,
      CONCAT_WS(' ', p.name_first, p.name_middle, p.name_last, p.name_suffix) AS full_name,
      COUNT(j.id) AS joined_opinion_count,
      COALESCE(pp.political_party_clean, 'Missing') AS political_party_clean
  FROM public.people_db_person p
  JOIN public.search_opinion_joined_by j
    ON j.person_id = p.id
  LEFT JOIN person_party pp
    ON pp.person_id = p.id
  GROUP BY p.id, p.name_first, p.name_middle, p.name_last, p.name_suffix, pp.political_party_clean
  ORDER BY joined_opinion_count DESC
  LIMIT 25
) TO STDOUT WITH CSV HEADER;
\o