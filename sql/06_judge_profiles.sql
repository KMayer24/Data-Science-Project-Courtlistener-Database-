-- 06_judge_profiles.sql
-- Descriptive statistics on judges / persons

-- Total number of persons
SELECT COUNT(*) AS total_persons
FROM public.people_db_person;

-- Political party distribution
SELECT political_party, COUNT(*) AS n
FROM public.people_db_politicalaffiliation
GROUP BY political_party
ORDER BY n DESC;

-- Position type distribution
SELECT position_type, COUNT(*) AS n
FROM public.people_db_position
GROUP BY position_type
ORDER BY n DESC;

-- Degree level distribution
SELECT degree_level, COUNT(*) AS n
FROM public.people_db_education
GROUP BY degree_level
ORDER BY n DESC;

-- Top 25 schools by number of education records
SELECT s.name,
       COUNT(e.id) AS education_count
FROM public.people_db_school s
JOIN public.people_db_education e
  ON e.school_id = s.id
GROUP BY s.name
ORDER BY education_count DESC
LIMIT 25;

-- Summary statistics: positions per person
SELECT MIN(position_count) AS min_positions_per_person,
       MAX(position_count) AS max_positions_per_person,
       AVG(position_count)::numeric(12,2) AS avg_positions_per_person
FROM (
    SELECT person_id, COUNT(*) AS position_count
    FROM public.people_db_position
    WHERE person_id IS NOT NULL
    GROUP BY person_id
) t;

-- Summary statistics: education records per person
SELECT MIN(education_count) AS min_education_per_person,
       MAX(education_count) AS max_education_per_person,
       AVG(education_count)::numeric(12,2) AS avg_education_per_person
FROM (
    SELECT person_id, COUNT(*) AS education_count
    FROM public.people_db_education
    WHERE person_id IS NOT NULL
    GROUP BY person_id
) t;

-- Missingness in people_db_person
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE gender IS NULL) AS missing_gender,
    COUNT(*) FILTER (WHERE religion IS NULL) AS missing_religion,
    COUNT(*) FILTER (WHERE date_dob IS NULL) AS missing_date_dob,
    COUNT(*) FILTER (WHERE has_photo IS NULL) AS missing_has_photo
FROM public.people_db_person;

-- Gender distribution
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
ORDER BY n DESC;

-- Persons with at least one active position
SELECT COUNT(DISTINCT person_id) AS persons_currently_active
FROM public.people_db_position
WHERE person_id IS NOT NULL
  AND date_termination IS NULL
  AND date_retirement IS NULL;

-- Persons without an active position
SELECT COUNT(DISTINCT p.id) AS persons_not_currently_active
FROM public.people_db_person p
LEFT JOIN (
    SELECT DISTINCT person_id
    FROM public.people_db_position
    WHERE person_id IS NOT NULL
      AND date_termination IS NULL
      AND date_retirement IS NULL
) a
  ON a.person_id = p.id
WHERE a.person_id IS NULL;

-- Active vs not active at person level
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
ORDER BY n DESC;

-- Gender by activity status
SELECT gender, activity_status, COUNT(*) AS n
FROM (
    SELECT
        p.id,
        p.gender,
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
GROUP BY gender, activity_status
ORDER BY gender, activity_status;

-- Persons with at least one currently active judicial position
SELECT COUNT(DISTINCT person_id) AS persons_currently_active_judicially
FROM public.people_db_position
WHERE person_id IS NOT NULL
  AND date_termination IS NULL
  AND date_retirement IS NULL
  AND position_type IN ('jud', 'pres-jud', 'trial-jud', 'mag', 'jus', 'act-jus', 'ass-jus',
                        'sup-jud', 'ass-jud', 'pres-jus', 'ret-senior-jud', 'c-jus',
                        'act-jud', 'spec-tr-jud', 'jud-pt', 'c-jud', 'ad-law-jud',
                        'ad-pres-jus', 'c-mag', 'c-spec-tr-jud', 'ret-act-jus',
                        'c-admin-jus', 'jus-pt', 'ret-jus');

-- Missingness in people_db_person
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE gender IS NULL OR TRIM(gender) = '') AS missing_gender,
    COUNT(*) FILTER (WHERE religion IS NULL OR TRIM(religion) = '') AS missing_religion,
    COUNT(*) FILTER (WHERE date_dob IS NULL) AS missing_date_dob,
    COUNT(*) FILTER (WHERE has_photo IS NULL) AS missing_has_photo
FROM public.people_db_person;