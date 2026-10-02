-- 05_verify_author_party_resolved.sql
-- Release regression for 04_author_party_resolved.sql. The rebuilt table is
-- the current 555,297-row standard. The legacy table has one fewer opinion;
-- every shared row must remain column-identical.
\pset pager off

SELECT 'row count original' AS check, count(*)::text AS value FROM ext.author_party_resolved
UNION ALL SELECT 'row count rebuilt', count(*)::text FROM ext.author_party_resolved_rebuilt
UNION ALL SELECT 'opinion_ids only in original',
  count(*)::text FROM (SELECT opinion_id FROM ext.author_party_resolved
                       EXCEPT SELECT opinion_id FROM ext.author_party_resolved_rebuilt) x
UNION ALL SELECT 'opinion_ids only in rebuilt',
  count(*)::text FROM (SELECT opinion_id FROM ext.author_party_resolved_rebuilt
                       EXCEPT SELECT opinion_id FROM ext.author_party_resolved) y;

\echo ''
\echo 'Per-column mismatches (0 = faithful):'
SELECT
  count(*) FILTER (WHERE o.judge_id IS DISTINCT FROM r.judge_id)                 AS judge_id,
  count(*) FILTER (WHERE o.judge_id_num IS DISTINCT FROM r.judge_id_num)         AS judge_id_num,
  count(*) FILTER (WHERE o.matched_person_id IS DISTINCT FROM r.matched_person_id) AS matched_person_id,
  count(*) FILTER (WHERE o.cl_political_party IS DISTINCT FROM r.cl_political_party) AS cl_party,
  count(*) FILTER (WHERE o.fjc_appointing_party IS DISTINCT FROM r.fjc_appointing_party) AS fjc_party,
  count(*) FILTER (WHERE o.fjc_appointment_match_quality IS DISTINCT FROM r.fjc_appointment_match_quality) AS fjc_quality,
  count(*) FILTER (WHERE o.party_final IS DISTINCT FROM r.party_final)           AS party_final,
  count(*) FILTER (WHERE o.party_source IS DISTINCT FROM r.party_source)         AS party_source,
  count(*) FILTER (WHERE o.gender IS DISTINCT FROM r.gender)                     AS gender,
  count(*) FILTER (WHERE o.channel IS DISTINCT FROM r.channel)                   AS channel
FROM ext.author_party_resolved o
JOIN ext.author_party_resolved_rebuilt r USING (opinion_id);

DO $$
DECLARE
  rebuilt_rows bigint;
  legacy_only bigint;
  release_only bigint;
  required_release_row boolean;
BEGIN
  SELECT count(*) INTO rebuilt_rows FROM ext.author_party_resolved_rebuilt;
  SELECT count(*) INTO legacy_only
  FROM (SELECT opinion_id FROM ext.author_party_resolved
        EXCEPT SELECT opinion_id FROM ext.author_party_resolved_rebuilt) x;
  SELECT count(*) INTO release_only
  FROM (SELECT opinion_id FROM ext.author_party_resolved_rebuilt
        EXCEPT SELECT opinion_id FROM ext.author_party_resolved) x;
  SELECT EXISTS (
    SELECT 1
  FROM ext.author_party_resolved_rebuilt
    WHERE opinion_id = 2966699 AND gender = 'm'
  ) INTO required_release_row;

  IF rebuilt_rows <> 555297 OR legacy_only <> 0 OR release_only <> 1
     OR NOT required_release_row THEN
    RAISE EXCEPTION
      'Party release regression failed: rows=%, legacy_only=%, release_only=%, required_release_row=%',
      rebuilt_rows, legacy_only, release_only, required_release_row;
  END IF;
END
$$;
