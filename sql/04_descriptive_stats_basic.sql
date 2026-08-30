-- 04_descriptive_stats_basic.sql
-- Descriptive statistics: basic / faster queries

-- 1. Core table sizes
SELECT 'search_court' AS table_name, COUNT(*) AS row_count FROM public.search_court
UNION ALL
SELECT 'people_db_person', COUNT(*) FROM public.people_db_person
UNION ALL
SELECT 'people_db_race', COUNT(*) FROM public.people_db_race
UNION ALL
SELECT 'people_db_person_race', COUNT(*) FROM public.people_db_person_race
UNION ALL
SELECT 'people_db_school', COUNT(*) FROM public.people_db_school
UNION ALL
SELECT 'people_db_position', COUNT(*) FROM public.people_db_position
UNION ALL
SELECT 'people_db_politicalaffiliation', COUNT(*) FROM public.people_db_politicalaffiliation
UNION ALL
SELECT 'people_db_education', COUNT(*) FROM public.people_db_education
UNION ALL
SELECT 'search_docket', COUNT(*) FROM public.search_docket
UNION ALL
SELECT 'search_opinioncluster', COUNT(*) FROM public.search_opinioncluster
UNION ALL
SELECT 'search_opinion', COUNT(*) FROM public.search_opinion
UNION ALL
SELECT 'search_opinioncluster_panel', COUNT(*) FROM public.search_opinioncluster_panel
UNION ALL
SELECT 'search_opinion_joined_by', COUNT(*) FROM public.search_opinion_joined_by
UNION ALL
SELECT 'search_opinioncluster_non_participating_judges', COUNT(*) FROM public.search_opinioncluster_non_participating_judges
UNION ALL
SELECT 'search_opinionscited', COUNT(*) FROM public.search_opinionscited
UNION ALL
SELECT 'search_citation', COUNT(*) FROM public.search_citation
ORDER BY table_name;

-- 2. Distributions of categorical variables
SELECT type, COUNT(*) AS n
FROM public.search_opinion
GROUP BY type
ORDER BY n DESC;

SELECT precedential_status, COUNT(*) AS n
FROM public.search_opinioncluster
GROUP BY precedential_status
ORDER BY n DESC;

SELECT source, COUNT(*) AS n
FROM public.search_docket
GROUP BY source
ORDER BY n DESC;

SELECT jurisdiction_type, COUNT(*) AS n
FROM public.search_docket
GROUP BY jurisdiction_type
ORDER BY n DESC;

SELECT position_type, COUNT(*) AS n
FROM public.people_db_position
GROUP BY position_type
ORDER BY n DESC;

SELECT political_party, COUNT(*) AS n
FROM public.people_db_politicalaffiliation
GROUP BY political_party
ORDER BY n DESC;

-- 3. Time distributions
SELECT EXTRACT(YEAR FROM date_filed) AS filing_year,
       COUNT(*) AS n
FROM public.search_opinioncluster
WHERE date_filed IS NOT NULL
GROUP BY EXTRACT(YEAR FROM date_filed)
ORDER BY filing_year;

SELECT EXTRACT(YEAR FROM date_filed) AS filing_year,
       COUNT(*) AS n
FROM public.search_docket
WHERE date_filed IS NOT NULL
GROUP BY EXTRACT(YEAR FROM date_filed)
ORDER BY filing_year;

SELECT EXTRACT(YEAR FROM date_start) AS start_year,
       COUNT(*) AS n
FROM public.people_db_position
WHERE date_start IS NOT NULL
GROUP BY EXTRACT(YEAR FROM date_start)
ORDER BY start_year;

SELECT degree_year, COUNT(*) AS n
FROM public.people_db_education
WHERE degree_year IS NOT NULL
GROUP BY degree_year
ORDER BY degree_year;

-- 4. Missingness / completeness
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE author_id IS NULL) AS missing_author_id,
    COUNT(*) FILTER (WHERE cluster_id IS NULL) AS missing_cluster_id,
    COUNT(*) FILTER (WHERE type IS NULL) AS missing_type,
    COUNT(*) FILTER (WHERE plain_text IS NULL) AS missing_plain_text,
    COUNT(*) FILTER (WHERE html IS NULL) AS missing_html
FROM public.search_opinion;

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE date_filed IS NULL) AS missing_date_filed,
    COUNT(*) FILTER (WHERE precedential_status IS NULL) AS missing_precedential_status,
    COUNT(*) FILTER (WHERE docket_id IS NULL) AS missing_docket_id,
    COUNT(*) FILTER (WHERE case_name IS NULL) AS missing_case_name
FROM public.search_opinioncluster;

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE date_filed IS NULL) AS missing_date_filed,
    COUNT(*) FILTER (WHERE court_id IS NULL) AS missing_court_id,
    COUNT(*) FILTER (WHERE source IS NULL) AS missing_source,
    COUNT(*) FILTER (WHERE jurisdiction_type IS NULL) AS missing_jurisdiction_type
FROM public.search_docket;

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE person_id IS NULL) AS missing_person_id,
    COUNT(*) FILTER (WHERE court_id IS NULL) AS missing_court_id,
    COUNT(*) FILTER (WHERE school_id IS NULL) AS missing_school_id,
    COUNT(*) FILTER (WHERE position_type IS NULL) AS missing_position_type
FROM public.people_db_position;

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE person_id IS NULL) AS missing_person_id,
    COUNT(*) FILTER (WHERE school_id IS NULL) AS missing_school_id,
    COUNT(*) FILTER (WHERE degree_year IS NULL) AS missing_degree_year
FROM public.people_db_education;