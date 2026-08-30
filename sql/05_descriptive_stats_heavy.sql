-- 05_descriptive_stats_heavy.sql
-- Descriptive statistics: heavy / slower queries

-- 1. Number of opinions per cluster
SELECT MIN(opinion_count) AS min_opinions_per_cluster,
       MAX(opinion_count) AS max_opinions_per_cluster,
       AVG(opinion_count)::numeric(12,2) AS avg_opinions_per_cluster
FROM (
    SELECT cluster_id, COUNT(*) AS opinion_count
    FROM public.search_opinion
    GROUP BY cluster_id
) t;

-- 2. Number of citations per cluster
SELECT MIN(citation_count) AS min_citations_per_cluster,
       MAX(citation_count) AS max_citations_per_cluster,
       AVG(citation_count)::numeric(12,2) AS avg_citations_per_cluster
FROM (
    SELECT cluster_id, COUNT(*) AS citation_count
    FROM public.search_citation
    GROUP BY cluster_id
) t;

-- 3. Number of outgoing citations per citing opinion
SELECT MIN(outdegree) AS min_outdegree,
       MAX(outdegree) AS max_outdegree,
       AVG(outdegree)::numeric(12,2) AS avg_outdegree
FROM (
    SELECT citing_opinion_id, COUNT(*) AS outdegree
    FROM public.search_opinionscited
    GROUP BY citing_opinion_id
) t;

-- 4. Panel members per opinion cluster
SELECT panel_size,
       COUNT(*) AS cluster_frequency
FROM (
    SELECT opinioncluster_id, COUNT(*) AS panel_size
    FROM public.search_opinioncluster_panel
    GROUP BY opinioncluster_id
) t
GROUP BY panel_size
ORDER BY panel_size;

SELECT MIN(panel_size) AS min_panel_size,
       MAX(panel_size) AS max_panel_size,
       AVG(panel_size)::numeric(12,2) AS avg_panel_size
FROM (
    SELECT opinioncluster_id, COUNT(*) AS panel_size
    FROM public.search_opinioncluster_panel
    GROUP BY opinioncluster_id
) t;

-- 5. Structural coverage
SELECT COUNT(*) AS opinions_without_cluster
FROM public.search_opinion
WHERE cluster_id IS NULL;

SELECT COUNT(*) AS clusters_without_opinions
FROM public.search_opinioncluster oc
LEFT JOIN public.search_opinion o
  ON o.cluster_id = oc.id
WHERE o.id IS NULL;

SELECT COUNT(*) AS dockets_without_clusters
FROM public.search_docket d
LEFT JOIN public.search_opinioncluster oc
  ON oc.docket_id = d.id
WHERE oc.id IS NULL;

-- 6. Top entities
-- 6. Top entities
SELECT c.full_name,
       COUNT(d.id) AS docket_count
FROM public.search_court c
JOIN public.search_docket d
  ON d.court_id = c.id
GROUP BY c.full_name
ORDER BY docket_count DESC
LIMIT 20;

SELECT oc.id,
       oc.case_name,
       COUNT(c.id) AS citation_count
FROM public.search_opinioncluster oc
JOIN public.search_citation c
  ON c.cluster_id = oc.id
GROUP BY oc.id, oc.case_name
ORDER BY citation_count DESC
LIMIT 20;