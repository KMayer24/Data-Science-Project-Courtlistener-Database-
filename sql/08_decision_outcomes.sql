-- 08_decision_outcomes.sql
-- Descriptive statistics on decision outcomes

-- Precedential status
SELECT precedential_status, COUNT(*) AS n
FROM public.search_opinioncluster
GROUP BY precedential_status
ORDER BY n DESC;

-- SCDB decision direction
SELECT scdb_decision_direction, COUNT(*) AS n
FROM public.search_opinioncluster
GROUP BY scdb_decision_direction
ORDER BY n DESC;

-- Majority vote distribution
SELECT scdb_votes_majority, COUNT(*) AS n
FROM public.search_opinioncluster
GROUP BY scdb_votes_majority
ORDER BY scdb_votes_majority;

-- Minority vote distribution
SELECT scdb_votes_minority, COUNT(*) AS n
FROM public.search_opinioncluster
GROUP BY scdb_votes_minority
ORDER BY scdb_votes_minority;

-- Distribution of opinion type
SELECT type, COUNT(*) AS n
FROM public.search_opinion
GROUP BY type
ORDER BY n DESC;

-- Per curiam decisions
SELECT per_curiam, COUNT(*) AS n
FROM public.search_opinion
GROUP BY per_curiam
ORDER BY n DESC;

-- Decision outcomes by filing year
SELECT EXTRACT(YEAR FROM date_filed) AS filing_year,
       precedential_status,
       COUNT(*) AS n
FROM public.search_opinioncluster
WHERE date_filed IS NOT NULL
GROUP BY EXTRACT(YEAR FROM date_filed), precedential_status
ORDER BY filing_year, precedential_status;

-- Decision direction by filing year
SELECT EXTRACT(YEAR FROM date_filed) AS filing_year,
       scdb_decision_direction,
       COUNT(*) AS n
FROM public.search_opinioncluster
WHERE date_filed IS NOT NULL
GROUP BY EXTRACT(YEAR FROM date_filed), scdb_decision_direction
ORDER BY filing_year, scdb_decision_direction;

-- Panel size by precedential status
SELECT
    COALESCE(oc.precedential_status, 'Missing') AS precedential_status,
    COUNT(p.id) AS panel_member_count
FROM public.search_opinioncluster oc
LEFT JOIN public.search_opinioncluster_panel p
  ON p.opinioncluster_id = oc.id
GROUP BY COALESCE(oc.precedential_status, 'Missing')
ORDER BY panel_member_count DESC;

-- Average panel size by precedential status
SELECT
    precedential_status,
    AVG(panel_size)::numeric(12,2) AS avg_panel_size
FROM (
    SELECT
        oc.id,
        COALESCE(oc.precedential_status, 'Missing') AS precedential_status,
        COUNT(p.id) AS panel_size
    FROM public.search_opinioncluster oc
    LEFT JOIN public.search_opinioncluster_panel p
      ON p.opinioncluster_id = oc.id
    GROUP BY oc.id, COALESCE(oc.precedential_status, 'Missing')
) t
GROUP BY precedential_status
ORDER BY avg_panel_size DESC;