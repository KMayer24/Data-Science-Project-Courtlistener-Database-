-- 15_clusters_by_year_tier_export.sql
-- Two exports for Figure 2, covering 1950-2026:
--   (a) cleaned_csv/clusters_by_year_tier.csv        court category x year
--   (b) cleaned_csv/clusters_by_year_provenance.csv  provenance x year
--
-- (a) Court categories. The detailed CourtListener jurisdictions are combined
-- into four functional categories suitable for the descriptive overview.
-- CourtListener assigns both the Supreme Court and the federal courts of
-- appeals to F. Remaining special, administrative, territorial, military and
-- uncommon jurisdictions are retained with state trial courts in the residual
-- fourth category.
--
-- (b) Provenance. This is read from search_opinioncluster.source, which records
-- where Free Law Project obtained the opinion record itself. Two earlier
-- versions of this export got this wrong:
--
--   * The first emitted RECAP as a fifth *court* category. That classified
--     records by provenance instead of by court and emptied the bands beside
--     it: in 2024, 10,217 of 17,287 federal appellate clusters left the
--     federal appellate band, which then read as ~7,000.
--   * The second kept the four court categories but read provenance from
--     search_docket.source bit 0. That bit marks a docket touched by RECAP,
--     which is not the same as an opinion obtained from RECAP. For federal
--     appellate opinions the two diverge completely: in 2025, 58 % of federal
--     appellate clusters sit on a RECAP-flagged docket, yet none of them has
--     a RECAP cluster source -- 109,232 of 112,241 come from court websites.
--     The docket flag describes the case file, not the opinion.
--
-- The cluster source codes are defined in CourtListener's ClusterSources
-- (cl/search/cluster_sources.py): C court website, R public.resource.org,
-- L lawbox, M manual input, A internet archive, Z columbia archive,
-- U Harvard Library Innovation Lab Case Law Access Project, D direct court
-- input, Q 2020 anonymous database, G recap, S scanning project. Multi-letter
-- values are merges, so a cluster can carry several sources: 24 % of clusters
-- in this range do. The counts below therefore overlap and must be read as
-- "records whose provenance includes X", not as a partition.
--
-- Note on the final year: the snapshot is dated 2026-03-31, so 2026 is a
-- partial year. The plotting script excludes it and the caption says so.

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
    AND EXTRACT(YEAR FROM oc.date_filed) BETWEEN 1950 AND 2026
  GROUP BY court_category, year
  ORDER BY year, court_category
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/clusters_by_year_provenance.csv
COPY (
  SELECT
      EXTRACT(YEAR FROM oc.date_filed)::int AS year,
      COUNT(*)                                        AS n_total,
      COUNT(*) FILTER (WHERE oc.source LIKE '%C%')    AS n_court_website,
      COUNT(*) FILTER (WHERE oc.source LIKE '%U%')    AS n_harvard,
      COUNT(*) FILTER (WHERE oc.source LIKE '%G%')    AS n_recap,
      COUNT(*) FILTER (WHERE oc.source ~ '[ZLRMADQS]') AS n_other_archives
  FROM public.search_opinioncluster oc
  WHERE oc.date_filed IS NOT NULL
    AND EXTRACT(YEAR FROM oc.date_filed) BETWEEN 1950 AND 2026
  GROUP BY year
  ORDER BY year
) TO STDOUT WITH CSV HEADER;
\o
