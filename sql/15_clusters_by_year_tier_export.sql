-- 15_clusters_by_year_tier_export.sql
-- Export annual opinion cluster counts by court category (1950-2020).
-- Joins: search_opinioncluster -> search_docket -> search_court (jurisdiction).
-- The detailed CourtListener jurisdictions are combined into four functional
-- categories suitable for the descriptive overview. CourtListener assigns
-- both the Supreme Court and the federal courts of appeals to F. Remaining
-- special, administrative, territorial, military, and uncommon jurisdictions
-- are retained with state trial courts in the residual fourth category.

\o /data/workspace/kmayer/courtlistener/cleaned_csv/clusters_by_year_tier.csv
COPY (
  SELECT
      CASE
          WHEN c.id = 'scotus' OR c.jurisdiction = 'F'
              THEN 'U.S. Supreme Court/Federal Appeals'
          WHEN c.jurisdiction IN ('FD', 'FB', 'FBP', 'FS')
              THEN 'Federal District/Bankruptcy/Special'
          WHEN c.jurisdiction IN ('S', 'SA')
              THEN 'State Supreme/Appellate'
          ELSE 'State Trial/Other'
      END AS court_category,
      EXTRACT(YEAR FROM oc.date_filed)::int AS year,
      COUNT(*) AS n
  FROM public.search_opinioncluster oc
  JOIN public.search_docket d  ON d.id  = oc.docket_id
  JOIN public.search_court  c  ON c.id  = d.court_id
  WHERE oc.date_filed IS NOT NULL
    AND EXTRACT(YEAR FROM oc.date_filed) BETWEEN 1950 AND 2020
  GROUP BY court_category, year
  ORDER BY year, court_category
) TO STDOUT WITH CSV HEADER;
\o
