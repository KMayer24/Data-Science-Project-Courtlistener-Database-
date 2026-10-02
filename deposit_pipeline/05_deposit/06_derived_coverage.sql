-- ============================================================
-- 06_derived_coverage.sql
--
-- Coverage checks for the derived (ext) layer. Complements the core
-- checks in sql/01_counts.sql, sql/02_fk_checks.sql and
-- sql/10_data_completeness.sql, which cover the public schema only.
--
-- Every figure the paper reports about the derived layer should be
-- reproducible from this file.
-- ============================================================

\pset pager off

\echo '== Corpus and court universe =='
SELECT (SELECT count(*) FROM ext.federal_appeal_opinions)        AS appellate_opinions,
       (SELECT count(*) FROM ext.federal_appeal_courts)          AS courts_included,
       (SELECT count(*) FROM ext.excluded_appeals_named_courts)  AS courts_excluded;

\echo ''
\echo '== Judge reference set =='
SELECT (SELECT count(*) FROM ext.fjc_judge_bio)       AS fjc_biographies,
       (SELECT count(*) FROM ext.fjc_judge_court)     AS fjc_service_records,
       (SELECT count(*) FROM ext.supplemental_judges) AS supplemental_records,
       (SELECT count(*) FROM ext.fjc_court_name_map)  AS court_name_mappings;

\echo ''
\echo '== Author attribution: resolution by step =='
SELECT attribution_step AS step,
       CASE attribution_step
           WHEN 1 THEN 'structured author_id'
           WHEN 2 THEN 'recorded author name'
           WHEN 3 THEN 'XML author element'
           WHEN 4 THEN 'HTML attribution formula'
       END AS step_label,
       count(*)                                        AS resolved,
       count(*) FILTER (WHERE person_unique)           AS person_unique,
       count(DISTINCT judge_id) FILTER (WHERE person_unique) AS distinct_judges
FROM ext.author_person_resolved
GROUP BY 1 ORDER BY 1;

\echo ''
\echo '== Author attribution: totals =='
SELECT (SELECT count(*) FROM ext.federal_appeal_opinions)             AS corpus,
       count(*)                                                        AS gender_resolved,
       round(100.0*count(*)/(SELECT count(*) FROM ext.federal_appeal_opinions), 2) AS pct_gender_resolved,
       count(*) FILTER (WHERE person_unique)                           AS person_unique,
       round(100.0*count(*) FILTER (WHERE person_unique)/count(*), 2)  AS pct_of_resolved,
       count(DISTINCT judge_id) FILTER (WHERE person_unique)           AS distinct_judges
FROM ext.author_person_resolved;

\echo ''
\echo '== Author attribution: identifier registry =='
SELECT id_registry, count(*) AS opinions, count(DISTINCT judge_id) AS judges
FROM ext.author_person_resolved WHERE person_unique
GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '== Author attribution: unmapped identifiers (must be 0) =='
SELECT count(*) AS unmapped FROM ext.author_person_resolved
WHERE person_unique AND id_registry = 'unmapped';

\echo ''
\echo '== Author party =='
SELECT party_source, count(*) AS opinions,
       round(100.0*count(*)/sum(count(*)) OVER (), 1) AS pct
FROM ext.author_party_resolved
WHERE party_final IS NOT NULL
GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '== Appellate FJC linkage =='
SELECT (SELECT count(*) FROM ext.fjc_appellate_raw_1971to2007) AS raw_1971_2007,
       (SELECT count(*) FROM ext.fjc_appellate_raw_2008plus)   AS raw_2008plus,
       (SELECT count(*) FROM ext.fjc_appellate_normalized)     AS normalized,
       (SELECT count(*) FROM ext.fjc_opinion_match)            AS opinion_matches,
       (SELECT count(*) FROM ext.opinion_fjc_covariates)       AS covariates,
       (SELECT count(*) FROM ext.opinion_fjc_covariates WHERE analysis_eligible) AS analysis_eligible;

\echo ''
\echo '== Appellate FJC linkage: match tiers =='
SELECT match_tier, count(*) AS opinions,
       count(*) FILTER (WHERE was_ambiguous) AS ambiguous
FROM ext.fjc_opinion_match GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '== Referential integrity of the derived layer (all must be 0) =='
SELECT
  (SELECT count(*) FROM ext.author_person_resolved r
     LEFT JOIN ext.federal_appeal_opinions o USING (opinion_id)
    WHERE o.opinion_id IS NULL)                        AS attribution_without_opinion,
  (SELECT count(*) FROM ext.author_party_resolved p
     LEFT JOIN ext.federal_appeal_opinions o USING (opinion_id)
    WHERE o.opinion_id IS NULL)                        AS party_without_opinion,
  (SELECT count(*) FROM ext.opinion_fjc_covariates c
     LEFT JOIN ext.federal_appeal_opinions o USING (opinion_id)
    WHERE o.opinion_id IS NULL)                        AS covariates_without_opinion,
  (SELECT count(*) FROM ext.federal_appeal_opinions o
     LEFT JOIN ext.federal_appeal_courts c ON c.id = o.court_id
    WHERE c.id IS NULL)                                AS opinion_outside_court_universe;
