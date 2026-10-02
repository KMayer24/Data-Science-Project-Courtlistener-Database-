-- ============================================================
-- 02_unique_person_attribution_export.sql
--
-- Exports for the person-level author attribution.
--   (a) summary by attribution step and matching tier   -> repository
--   (b) summary by step only                            -> repository
--   (c) one row per uniquely attributed opinion         -> data deposit
--
-- Prerequisite: 01_unique_person_attribution.sql
-- Run from the repository root:
--   psql -p 5432 -d courtcase_db -f sql/derived/02_unique_person_attribution_export.sql
-- ============================================================

\pset pager off

-- (a) Step x tier breakdown -------------------------------------------------
\copy (SELECT attribution_step AS step, tier, tier_label, count(*) AS resolved, count(*) FILTER (WHERE person_unique) AS person_unique, round(100.0*count(*) FILTER (WHERE person_unique)/count(*),1) AS pct_unique FROM ext.author_person_resolved GROUP BY 1,2,3 ORDER BY 1,2) TO 'cleaned_csv/author_person_unique_by_step_tier.csv' CSV HEADER

-- (b) Step level summary ----------------------------------------------------
\copy (SELECT attribution_step AS step, CASE attribution_step WHEN 1 THEN 'structured author_id' WHEN 2 THEN 'recorded author name' WHEN 3 THEN 'XML author element' WHEN 4 THEN 'HTML attribution formula' END AS step_label, count(*) AS resolved, count(*) FILTER (WHERE person_unique) AS person_unique, count(DISTINCT judge_id) FILTER (WHERE person_unique) AS distinct_judges FROM ext.author_person_resolved GROUP BY 1 ORDER BY 1) TO 'cleaned_csv/author_person_unique_by_step.csv' CSV HEADER

-- (c) Identifier registry ---------------------------------------------------
\copy (SELECT id_registry, count(*) AS opinions, count(DISTINCT judge_id) AS judges FROM ext.author_person_resolved WHERE person_unique GROUP BY 1 ORDER BY 2 DESC) TO 'cleaned_csv/author_person_unique_by_registry.csv' CSV HEADER

-- (d) Per-opinion export for the deposit ------------------------------------
\copy (SELECT opinion_id, cluster_id, court_id, court_short_name, year_filed, attribution_step, tier, tier_label, id_registry, cl_person_id, fjc_nid, sup_id, judge_id, judge_display_name, gender FROM ext.author_person_resolved WHERE person_unique ORDER BY opinion_id) TO 'export/deposit/author_person_unique.csv' CSV HEADER
