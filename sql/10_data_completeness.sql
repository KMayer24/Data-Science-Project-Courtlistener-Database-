DROP VIEW IF EXISTS data_completeness_overview;

CREATE VIEW data_completeness_overview AS

SELECT
    'people_db_person' AS table_name,
    'name_first' AS variable_name,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE name_first IS NULL OR TRIM(name_first) = '') AS missing_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE name_first IS NULL OR TRIM(name_first) = '') / COUNT(*),
        2
    ) AS missing_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE name_first IS NOT NULL AND TRIM(name_first) <> '') / COUNT(*),
        2
    ) AS completeness_pct
FROM public.people_db_person

UNION ALL

SELECT
    'people_db_person',
    'name_last',
    COUNT(*),
    COUNT(*) FILTER (WHERE name_last IS NULL OR TRIM(name_last) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE name_last IS NULL OR TRIM(name_last) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE name_last IS NOT NULL AND TRIM(name_last) <> '') / COUNT(*), 2)
FROM public.people_db_person

UNION ALL

SELECT
    'people_db_person',
    'date_dob',
    COUNT(*),
    COUNT(*) FILTER (WHERE date_dob IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_dob IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_dob IS NOT NULL) / COUNT(*), 2)
FROM public.people_db_person

UNION ALL

SELECT
    'people_db_person',
    'gender',
    COUNT(*),
    COUNT(*) FILTER (WHERE gender IS NULL OR TRIM(gender) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE gender IS NULL OR TRIM(gender) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE gender IS NOT NULL AND TRIM(gender) <> '') / COUNT(*), 2)
FROM public.people_db_person

UNION ALL

SELECT
    'people_db_person',
    'religion',
    COUNT(*),
    COUNT(*) FILTER (WHERE religion IS NULL OR TRIM(religion) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE religion IS NULL OR TRIM(religion) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE religion IS NOT NULL AND TRIM(religion) <> '') / COUNT(*), 2)
FROM public.people_db_person

UNION ALL

SELECT
    'people_db_person',
    'has_photo',
    COUNT(*),
    COUNT(*) FILTER (WHERE has_photo IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE has_photo IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE has_photo IS NOT NULL) / COUNT(*), 2)
FROM public.people_db_person

UNION ALL

SELECT
    'people_db_position',
    'position_type',
    COUNT(*),
    COUNT(*) FILTER (WHERE position_type IS NULL OR TRIM(position_type) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE position_type IS NULL OR TRIM(position_type) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE position_type IS NOT NULL AND TRIM(position_type) <> '') / COUNT(*), 2)
FROM public.people_db_position

UNION ALL

SELECT
    'people_db_position',
    'job_title',
    COUNT(*),
    COUNT(*) FILTER (WHERE job_title IS NULL OR TRIM(job_title) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE job_title IS NULL OR TRIM(job_title) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE job_title IS NOT NULL AND TRIM(job_title) <> '') / COUNT(*), 2)
FROM public.people_db_position

UNION ALL

SELECT
    'people_db_position',
    'organization_name',
    COUNT(*),
    COUNT(*) FILTER (WHERE organization_name IS NULL OR TRIM(organization_name) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE organization_name IS NULL OR TRIM(organization_name) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE organization_name IS NOT NULL AND TRIM(organization_name) <> '') / COUNT(*), 2)
FROM public.people_db_position

UNION ALL

SELECT
    'people_db_position',
    'date_start',
    COUNT(*),
    COUNT(*) FILTER (WHERE date_start IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_start IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_start IS NOT NULL) / COUNT(*), 2)
FROM public.people_db_position

UNION ALL

SELECT
    'people_db_position',
    'date_termination',
    COUNT(*),
    COUNT(*) FILTER (WHERE date_termination IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_termination IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_termination IS NOT NULL) / COUNT(*), 2)
FROM public.people_db_position

UNION ALL

SELECT
    'people_db_position',
    'how_selected',
    COUNT(*),
    COUNT(*) FILTER (WHERE how_selected IS NULL OR TRIM(how_selected) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE how_selected IS NULL OR TRIM(how_selected) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE how_selected IS NOT NULL AND TRIM(how_selected) <> '') / COUNT(*), 2)
FROM public.people_db_position

UNION ALL

SELECT
    'people_db_position',
    'court_id',
    COUNT(*),
    COUNT(*) FILTER (WHERE court_id IS NULL OR TRIM(court_id) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE court_id IS NULL OR TRIM(court_id) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE court_id IS NOT NULL AND TRIM(court_id) <> '') / COUNT(*), 2)
FROM public.people_db_position

UNION ALL

SELECT
    'people_db_education',
    'degree_level',
    COUNT(*),
    COUNT(*) FILTER (WHERE degree_level IS NULL OR TRIM(degree_level) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE degree_level IS NULL OR TRIM(degree_level) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE degree_level IS NOT NULL AND TRIM(degree_level) <> '') / COUNT(*), 2)
FROM public.people_db_education

UNION ALL

SELECT
    'people_db_education',
    'degree_detail',
    COUNT(*),
    COUNT(*) FILTER (WHERE degree_detail IS NULL OR TRIM(degree_detail) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE degree_detail IS NULL OR TRIM(degree_detail) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE degree_detail IS NOT NULL AND TRIM(degree_detail) <> '') / COUNT(*), 2)
FROM public.people_db_education

UNION ALL

SELECT
    'people_db_education',
    'degree_year',
    COUNT(*),
    COUNT(*) FILTER (WHERE degree_year IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE degree_year IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE degree_year IS NOT NULL) / COUNT(*), 2)
FROM public.people_db_education

UNION ALL

SELECT
    'people_db_education',
    'school_id',
    COUNT(*),
    COUNT(*) FILTER (WHERE school_id IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE school_id IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE school_id IS NOT NULL) / COUNT(*), 2)
FROM public.people_db_education

UNION ALL

SELECT
    'people_db_school',
    'name',
    COUNT(*),
    COUNT(*) FILTER (WHERE name IS NULL OR TRIM(name) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE name IS NULL OR TRIM(name) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE name IS NOT NULL AND TRIM(name) <> '') / COUNT(*), 2)
FROM public.people_db_school

UNION ALL

SELECT
    'people_db_school',
    'ein',
    COUNT(*),
    COUNT(*) FILTER (WHERE ein IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE ein IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE ein IS NOT NULL) / COUNT(*), 2)
FROM public.people_db_school

UNION ALL

SELECT
    'people_db_politicalaffiliation',
    'political_party',
    COUNT(*),
    COUNT(*) FILTER (WHERE political_party IS NULL OR TRIM(political_party) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE political_party IS NULL OR TRIM(political_party) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE political_party IS NOT NULL AND TRIM(political_party) <> '') / COUNT(*), 2)
FROM public.people_db_politicalaffiliation

UNION ALL

SELECT
    'people_db_politicalaffiliation',
    'date_start',
    COUNT(*),
    COUNT(*) FILTER (WHERE date_start IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_start IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_start IS NOT NULL) / COUNT(*), 2)
FROM public.people_db_politicalaffiliation

UNION ALL

SELECT
    'people_db_politicalaffiliation',
    'date_end',
    COUNT(*),
    COUNT(*) FILTER (WHERE date_end IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_end IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_end IS NOT NULL) / COUNT(*), 2)
FROM public.people_db_politicalaffiliation

UNION ALL

SELECT
    'search_court',
    'full_name',
    COUNT(*),
    COUNT(*) FILTER (WHERE full_name IS NULL OR TRIM(full_name) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE full_name IS NULL OR TRIM(full_name) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE full_name IS NOT NULL AND TRIM(full_name) <> '') / COUNT(*), 2)
FROM public.search_court

UNION ALL

SELECT
    'search_court',
    'short_name',
    COUNT(*),
    COUNT(*) FILTER (WHERE short_name IS NULL OR TRIM(short_name) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE short_name IS NULL OR TRIM(short_name) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE short_name IS NOT NULL AND TRIM(short_name) <> '') / COUNT(*), 2)
FROM public.search_court

UNION ALL

SELECT
    'search_court',
    'jurisdiction',
    COUNT(*),
    COUNT(*) FILTER (WHERE jurisdiction IS NULL OR TRIM(jurisdiction) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE jurisdiction IS NULL OR TRIM(jurisdiction) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE jurisdiction IS NOT NULL AND TRIM(jurisdiction) <> '') / COUNT(*), 2)
FROM public.search_court

UNION ALL

SELECT
    'search_court',
    'parent_court_id',
    COUNT(*),
    COUNT(*) FILTER (WHERE parent_court_id IS NULL OR TRIM(parent_court_id) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE parent_court_id IS NULL OR TRIM(parent_court_id) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE parent_court_id IS NOT NULL AND TRIM(parent_court_id) <> '') / COUNT(*), 2)
FROM public.search_court

UNION ALL

SELECT
    'search_docket',
    'court_id',
    COUNT(*),
    COUNT(*) FILTER (WHERE court_id IS NULL OR TRIM(court_id) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE court_id IS NULL OR TRIM(court_id) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE court_id IS NOT NULL AND TRIM(court_id) <> '') / COUNT(*), 2)
FROM public.search_docket

UNION ALL

SELECT
    'search_docket',
    'date_filed',
    COUNT(*),
    COUNT(*) FILTER (WHERE date_filed IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_filed IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_filed IS NOT NULL) / COUNT(*), 2)
FROM public.search_docket

UNION ALL

SELECT
    'search_docket',
    'case_name',
    COUNT(*),
    COUNT(*) FILTER (WHERE case_name IS NULL OR TRIM(case_name) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE case_name IS NULL OR TRIM(case_name) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE case_name IS NOT NULL AND TRIM(case_name) <> '') / COUNT(*), 2)
FROM public.search_docket

UNION ALL

SELECT
    'search_docket',
    'case_name_short',
    COUNT(*),
    COUNT(*) FILTER (WHERE case_name_short IS NULL OR TRIM(case_name_short) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE case_name_short IS NULL OR TRIM(case_name_short) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE case_name_short IS NOT NULL AND TRIM(case_name_short) <> '') / COUNT(*), 2)
FROM public.search_docket

UNION ALL

SELECT
    'search_docket',
    'jurisdiction_type',
    COUNT(*),
    COUNT(*) FILTER (WHERE jurisdiction_type IS NULL OR TRIM(jurisdiction_type) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE jurisdiction_type IS NULL OR TRIM(jurisdiction_type) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE jurisdiction_type IS NOT NULL AND TRIM(jurisdiction_type) <> '') / COUNT(*), 2)
FROM public.search_docket

UNION ALL

SELECT
    'search_docket',
    'nature_of_suit',
    COUNT(*),
    COUNT(*) FILTER (WHERE nature_of_suit IS NULL OR TRIM(nature_of_suit) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE nature_of_suit IS NULL OR TRIM(nature_of_suit) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE nature_of_suit IS NOT NULL AND TRIM(nature_of_suit) <> '') / COUNT(*), 2)
FROM public.search_docket

UNION ALL

SELECT
    'search_opinioncluster',
    'date_filed',
    COUNT(*),
    COUNT(*) FILTER (WHERE date_filed IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_filed IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE date_filed IS NOT NULL) / COUNT(*), 2)
FROM public.search_opinioncluster

UNION ALL

SELECT
    'search_opinioncluster',
    'case_name',
    COUNT(*),
    COUNT(*) FILTER (WHERE case_name IS NULL OR TRIM(case_name) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE case_name IS NULL OR TRIM(case_name) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE case_name IS NOT NULL AND TRIM(case_name) <> '') / COUNT(*), 2)
FROM public.search_opinioncluster

UNION ALL

SELECT
    'search_opinioncluster',
    'precedential_status',
    COUNT(*),
    COUNT(*) FILTER (WHERE precedential_status IS NULL OR TRIM(precedential_status) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE precedential_status IS NULL OR TRIM(precedential_status) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE precedential_status IS NOT NULL AND TRIM(precedential_status) <> '') / COUNT(*), 2)
FROM public.search_opinioncluster

UNION ALL

SELECT
    'search_opinioncluster',
    'disposition',
    COUNT(*),
    COUNT(*) FILTER (WHERE disposition IS NULL OR TRIM(disposition) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE disposition IS NULL OR TRIM(disposition) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE disposition IS NOT NULL AND TRIM(disposition) <> '') / COUNT(*), 2)
FROM public.search_opinioncluster

UNION ALL

SELECT
    'search_opinioncluster',
    'citation_count',
    COUNT(*),
    COUNT(*) FILTER (WHERE citation_count IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE citation_count IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE citation_count IS NOT NULL) / COUNT(*), 2)
FROM public.search_opinioncluster

UNION ALL

SELECT
    'search_citation',
    'reporter',
    COUNT(*),
    COUNT(*) FILTER (WHERE reporter IS NULL OR TRIM(reporter) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE reporter IS NULL OR TRIM(reporter) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE reporter IS NOT NULL AND TRIM(reporter) <> '') / COUNT(*), 2)
FROM public.search_citation

UNION ALL

SELECT
    'search_citation',
    'page',
    COUNT(*),
    COUNT(*) FILTER (WHERE page IS NULL OR TRIM(page) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE page IS NULL OR TRIM(page) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE page IS NOT NULL AND TRIM(page) <> '') / COUNT(*), 2)
FROM public.search_citation

UNION ALL

SELECT
    'search_citation',
    'type',
    COUNT(*),
    COUNT(*) FILTER (WHERE type IS NULL OR TRIM(type) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE type IS NULL OR TRIM(type) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE type IS NOT NULL AND TRIM(type) <> '') / COUNT(*), 2)
FROM public.search_citation

UNION ALL

SELECT
    'search_citation',
    'cluster_id',
    COUNT(*),
    COUNT(*) FILTER (WHERE cluster_id IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE cluster_id IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE cluster_id IS NOT NULL) / COUNT(*), 2)
FROM public.search_citation

UNION ALL

SELECT
    'search_opinion',
    'type',
    COUNT(*),
    COUNT(*) FILTER (WHERE type IS NULL OR TRIM(type) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE type IS NULL OR TRIM(type) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE type IS NOT NULL AND TRIM(type) <> '') / COUNT(*), 2)
FROM public.search_opinion

UNION ALL

SELECT
    'search_opinion',
    'author_id',
    COUNT(*),
    COUNT(*) FILTER (WHERE author_id IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE author_id IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE author_id IS NOT NULL) / COUNT(*), 2)
FROM public.search_opinion

UNION ALL

SELECT
    'search_opinion',
    'author_str',
    COUNT(*),
    COUNT(*) FILTER (WHERE author_str IS NULL OR TRIM(author_str) = ''),
    ROUND(100.0 * COUNT(*) FILTER (WHERE author_str IS NULL OR TRIM(author_str) = '') / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE author_str IS NOT NULL AND TRIM(author_str) <> '') / COUNT(*), 2)
FROM public.search_opinion

UNION ALL

SELECT
    'search_opinion',
    'cluster_id',
    COUNT(*),
    COUNT(*) FILTER (WHERE cluster_id IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE cluster_id IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE cluster_id IS NOT NULL) / COUNT(*), 2)
FROM public.search_opinion

UNION ALL

SELECT
    'search_opinion',
    'per_curiam',
    COUNT(*),
    COUNT(*) FILTER (WHERE per_curiam IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE per_curiam IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE per_curiam IS NOT NULL) / COUNT(*), 2)
FROM public.search_opinion

UNION ALL

SELECT
    'search_opinion',
    'page_count',
    COUNT(*),
    COUNT(*) FILTER (WHERE page_count IS NULL),
    ROUND(100.0 * COUNT(*) FILTER (WHERE page_count IS NULL) / COUNT(*), 2),
    ROUND(100.0 * COUNT(*) FILTER (WHERE page_count IS NOT NULL) / COUNT(*), 2)
FROM public.search_opinion

UNION ALL

SELECT
    'search_opinion',
    'any_text_available',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE COALESCE(NULLIF(TRIM(plain_text), ''), NULLIF(TRIM(html), ''), NULLIF(TRIM(html_lawbox), ''),
                       NULLIF(TRIM(html_columbia), ''), NULLIF(TRIM(html_anon_2020), ''), NULLIF(TRIM(xml_harvard), ''),
                       NULLIF(TRIM(xml_scan), ''), NULLIF(TRIM(html_with_citations), '')) IS NULL
    ),
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE COALESCE(NULLIF(TRIM(plain_text), ''), NULLIF(TRIM(html), ''), NULLIF(TRIM(html_lawbox), ''),
                           NULLIF(TRIM(html_columbia), ''), NULLIF(TRIM(html_anon_2020), ''), NULLIF(TRIM(xml_harvard), ''),
                           NULLIF(TRIM(xml_scan), ''), NULLIF(TRIM(html_with_citations), '')) IS NULL
        ) / COUNT(*),
        2
    ),
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE COALESCE(NULLIF(TRIM(plain_text), ''), NULLIF(TRIM(html), ''), NULLIF(TRIM(html_lawbox), ''),
                           NULLIF(TRIM(html_columbia), ''), NULLIF(TRIM(html_anon_2020), ''), NULLIF(TRIM(xml_harvard), ''),
                           NULLIF(TRIM(xml_scan), ''), NULLIF(TRIM(html_with_citations), '')) IS NOT NULL
        ) / COUNT(*),
        2
    )
FROM public.search_opinion
;