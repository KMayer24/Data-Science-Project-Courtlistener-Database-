-- 16_citation_buckets_export.sql
-- Export distribution of incoming citations per opinion cluster (filed 1950-2010).
-- Bucketed into: 0, 1-5, 6-20, 21-100, 100+.
-- Restricted to 1950-2010 to avoid right-censoring bias for recent opinions.

\o /data/workspace/kmayer/courtlistener/cleaned_csv/citation_buckets.csv
COPY (
  SELECT
      CASE
          WHEN cit.citation_count = 0              THEN '0 (never cited)'
          WHEN cit.citation_count BETWEEN 1 AND 5   THEN '1-5'
          WHEN cit.citation_count BETWEEN 6 AND 20  THEN '6-20'
          WHEN cit.citation_count BETWEEN 21 AND 100 THEN '21-100'
          ELSE '100+'
      END AS bucket,
      COUNT(*) AS n_clusters
  FROM (
      SELECT
          oc.id,
          COUNT(osc.id) AS citation_count
      FROM public.search_opinioncluster oc
      LEFT JOIN public.search_opinion      so  ON so.cluster_id       = oc.id
      LEFT JOIN public.search_opinionscited osc ON osc.cited_opinion_id = so.id
      WHERE oc.date_filed IS NOT NULL
        AND EXTRACT(YEAR FROM oc.date_filed) BETWEEN 1950 AND 2010
      GROUP BY oc.id
  ) cit
  GROUP BY bucket
  ORDER BY MIN(cit.citation_count)
) TO STDOUT WITH CSV HEADER;
\o
