-- 06_judge_profiles_export.sql
-- Export judge/person profile statistics to CSV files

\o /data/workspace/kmayer/courtlistener/cleaned_csv/judge_total_persons.csv
COPY (
  SELECT COUNT(*) AS total_persons
  FROM public.people_db_person
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/judge_political_party_distribution.csv
COPY (
  SELECT
    CASE
      WHEN political_party IS NULL OR TRIM(political_party) = '' THEN 'Missing'
      ELSE political_party
    END AS political_party_clean,
    COUNT(*) AS n
  FROM public.people_db_politicalaffiliation
  GROUP BY
    CASE
      WHEN political_party IS NULL OR TRIM(political_party) = '' THEN 'Missing'
      ELSE political_party
    END
  ORDER BY n DESC
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/judge_degree_level_distribution.csv
COPY (
  SELECT
    CASE
      WHEN degree_level IS NULL OR TRIM(degree_level) = '' THEN 'Missing'
      ELSE degree_level
    END AS degree_level_clean,
    COUNT(*) AS n
  FROM public.people_db_education
  GROUP BY
    CASE
      WHEN degree_level IS NULL OR TRIM(degree_level) = '' THEN 'Missing'
      ELSE degree_level
    END
  ORDER BY n DESC
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/judge_top25_schools.csv
COPY (
  SELECT s.name,
         COUNT(e.id) AS education_count
  FROM public.people_db_school s
  JOIN public.people_db_education e
    ON e.school_id = s.id
  GROUP BY s.name
  ORDER BY education_count DESC
  LIMIT 25
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/judge_positions_per_person_summary.csv
COPY (
  SELECT MIN(position_count) AS min_positions_per_person,
         MAX(position_count) AS max_positions_per_person,
         AVG(position_count)::numeric(12,2) AS avg_positions_per_person
  FROM (
      SELECT person_id, COUNT(*) AS position_count
      FROM public.people_db_position
      WHERE person_id IS NOT NULL
      GROUP BY person_id
  ) t
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/judge_education_per_person_summary.csv
COPY (
  SELECT MIN(education_count) AS min_education_per_person,
         MAX(education_count) AS max_education_per_person,
         AVG(education_count)::numeric(12,2) AS avg_education_per_person
  FROM (
      SELECT person_id, COUNT(*) AS education_count
      FROM public.people_db_education
      WHERE person_id IS NOT NULL
      GROUP BY person_id
  ) t
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/judge_gender_distribution.csv
COPY (
  SELECT
    CASE
      WHEN gender IS NULL OR TRIM(gender) = '' THEN 'Missing'
      ELSE gender
    END AS gender_clean,
    COUNT(*) AS n
  FROM public.people_db_person
  GROUP BY
    CASE
      WHEN gender IS NULL OR TRIM(gender) = '' THEN 'Missing'
      ELSE gender
    END
  ORDER BY n DESC
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/judge_activity_status.csv
COPY (
  SELECT activity_status, COUNT(*) AS n
  FROM (
      SELECT
          p.id,
          CASE
              WHEN EXISTS (
                  SELECT 1
                  FROM public.people_db_position pp
                  WHERE pp.person_id = p.id
                    AND pp.date_termination IS NULL
                    AND pp.date_retirement IS NULL
              )
              THEN 'active'
              ELSE 'not_active'
          END AS activity_status
      FROM public.people_db_person p
  ) t
  GROUP BY activity_status
  ORDER BY n DESC
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/judge_gender_by_activity_status.csv
COPY (
  SELECT gender_clean, activity_status, COUNT(*) AS n
  FROM (
      SELECT
          p.id,
          CASE
              WHEN p.gender IS NULL OR TRIM(p.gender) = '' THEN 'Missing'
              ELSE p.gender
          END AS gender_clean,
          CASE
              WHEN EXISTS (
                  SELECT 1
                  FROM public.people_db_position pp
                  WHERE pp.person_id = p.id
                    AND pp.date_termination IS NULL
                    AND pp.date_retirement IS NULL
              )
              THEN 'active'
              ELSE 'not_active'
          END AS activity_status
      FROM public.people_db_person p
  ) t
  GROUP BY gender_clean, activity_status
  ORDER BY gender_clean, activity_status
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/judge_currently_active_judicially.csv
COPY (
  SELECT COUNT(DISTINCT person_id) AS persons_currently_active_judicially
  FROM public.people_db_position
  WHERE person_id IS NOT NULL
    AND date_termination IS NULL
    AND date_retirement IS NULL
    AND position_type IN (
      'jud','pres-jud','trial-jud','mag','jus','act-jus','ass-jus',
      'sup-jud','ass-jud','pres-jus','ret-senior-jud','c-jus',
      'act-jud','spec-tr-jud','jud-pt','c-jud','ad-law-jud',
      'ad-pres-jus','c-mag','c-spec-tr-jud','ret-act-jus',
      'c-admin-jus','jus-pt','ret-jus'
    )
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/judge_missingness.csv
COPY (
  SELECT
      COUNT(*) AS total_rows,
      COUNT(*) FILTER (WHERE gender IS NULL OR TRIM(gender) = '') AS missing_gender,
      COUNT(*) FILTER (WHERE religion IS NULL OR TRIM(religion) = '') AS missing_religion,
      COUNT(*) FILTER (WHERE date_dob IS NULL) AS missing_date_dob,
      COUNT(*) FILTER (WHERE has_photo IS NULL) AS missing_has_photo
  FROM public.people_db_person
) TO STDOUT WITH CSV HEADER;
\o