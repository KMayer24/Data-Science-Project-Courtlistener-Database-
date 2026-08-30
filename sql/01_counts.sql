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