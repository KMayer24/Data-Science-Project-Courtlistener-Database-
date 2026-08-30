-- 07_judge_careers.sql
-- Descriptive statistics on judicial and political careers

-- Persons with political affiliations
SELECT COUNT(DISTINCT person_id) AS persons_with_political_affiliation
FROM public.people_db_politicalaffiliation
WHERE person_id IS NOT NULL;

-- Persons with at least one recorded position
SELECT COUNT(DISTINCT person_id) AS persons_with_positions
FROM public.people_db_position
WHERE person_id IS NOT NULL;

-- Career start year distribution
SELECT EXTRACT(YEAR FROM date_start) AS start_year,
       COUNT(*) AS n
FROM public.people_db_position
WHERE date_start IS NOT NULL
GROUP BY EXTRACT(YEAR FROM date_start)
ORDER BY start_year;

-- Career end / termination year distribution
SELECT EXTRACT(YEAR FROM date_termination) AS termination_year,
       COUNT(*) AS n
FROM public.people_db_position
WHERE date_termination IS NOT NULL
GROUP BY EXTRACT(YEAR FROM date_termination)
ORDER BY termination_year;

-- Cross-tab: political party by position type
SELECT
    COALESCE(pa.political_party, 'Missing') AS political_party,
    COALESCE(pp.position_type, 'Missing') AS position_type,
    COUNT(*) AS n
FROM public.people_db_position pp
LEFT JOIN public.people_db_politicalaffiliation pa
  ON pa.person_id = pp.person_id
GROUP BY COALESCE(pa.political_party, 'Missing'),
         COALESCE(pp.position_type, 'Missing')
ORDER BY n DESC;

-- Persons with multiple position types
SELECT position_type_count,
       COUNT(*) AS person_frequency
FROM (
    SELECT person_id, COUNT(DISTINCT position_type) AS position_type_count
    FROM public.people_db_position
    WHERE person_id IS NOT NULL
    GROUP BY person_id
) t
GROUP BY position_type_count
ORDER BY position_type_count;

-- Top 25 courts appearing in careers
SELECT c.full_name,
       COUNT(p.id) AS position_count
FROM public.people_db_position p
JOIN public.search_court c
  ON c.id = p.court_id
GROUP BY c.full_name
ORDER BY position_count DESC
LIMIT 25;

-- Top 25 appointing persons / appointers
SELECT appointer_id,
       COUNT(*) AS n
FROM public.people_db_position
WHERE appointer_id IS NOT NULL
GROUP BY appointer_id
ORDER BY n DESC
LIMIT 25;