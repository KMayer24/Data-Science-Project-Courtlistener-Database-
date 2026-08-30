SELECT COUNT(*) AS missing_citing
FROM public.search_opinionscited s
LEFT JOIN public.search_opinion o
  ON o.id = s.citing_opinion_id
WHERE o.id IS NULL;

SELECT COUNT(*) AS missing_cited
FROM public.search_opinionscited s
LEFT JOIN public.search_opinion o
  ON o.id = s.cited_opinion_id
WHERE o.id IS NULL;

SELECT COUNT(*) AS missing_cluster
FROM public.search_citation c
LEFT JOIN public.search_opinioncluster oc
  ON oc.id = c.cluster_id
WHERE oc.id IS NULL;

SELECT COUNT(*) - COUNT(DISTINCT id) AS duplicate_opinion_ids
FROM public.search_opinion;

SELECT COUNT(*) - COUNT(DISTINCT id) AS duplicate_cluster_ids
FROM public.search_opinioncluster;

SELECT COUNT(*) - COUNT(DISTINCT id) AS duplicate_opinionscited_ids
FROM public.search_opinionscited;

SELECT COUNT(*) - COUNT(DISTINCT id) AS duplicate_citation_ids
FROM public.search_citation;

SELECT COUNT(*) - COUNT(DISTINCT id) AS duplicate_docket_ids
FROM public.search_docket;