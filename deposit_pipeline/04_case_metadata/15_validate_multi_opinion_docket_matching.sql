/*
===============================================================================
15_validate_multi_opinion_docket_matching.sql
===============================================================================

Purpose
-------
Validate that the CourtListener-to-FJC linkage preserves the expected
one-to-many relationship:

    one CourtListener docket / one FJC appeal
        -> potentially multiple individual CourtListener opinions

The unit of the final table remains opinion_id. This script does NOT collapse
multiple opinions into one row. Instead, it tests whether opinions belonging
to the same docket or cluster are mapped consistently.

Required temporary tables
-------------------------
Run in the same psql session after scripts 12, 13, and 14:

    tmp_fjc_opinion_match_test
    tmp_fjc_match_confidence
    tmp_fjc_ambiguous_candidates
    tmp_fjc_opinion_final_match

Main checks
-----------
1. Exactly one result row per opinion_id.
2. Multiple opinions per docket_id are preserved.
3. Multiple opinions per normalized court+docket are preserved.
4. Opinions sharing a docket_id do not select conflicting FJC appeals.
5. Opinions sharing a cluster_id do not select conflicting FJC appeals.
6. Opinions sharing court+normalized docket do not select conflicting appeals.
7. One selected FJC appeal may legitimately have multiple opinions.
8. Suspicious cases: many unrelated clusters, wide date spans, mixed statuses.
9. Negative controls: wrong circuit and shifted docket year.
10. Reproducible review samples.

No permanent tables are created.
===============================================================================
*/

\pset pager off
\timing on


/*
===============================================================================
1. Fundamental grain: exactly one row per individual opinion
===============================================================================
*/

SELECT
    COUNT(*) AS n_rows,
    COUNT(DISTINCT opinion_id) AS n_distinct_opinions,
    COUNT(*) - COUNT(DISTINCT opinion_id) AS duplicate_opinion_rows
FROM tmp_fjc_opinion_final_match;

SELECT
    opinion_id,
    COUNT(*) AS n_rows
FROM tmp_fjc_opinion_final_match
GROUP BY opinion_id
HAVING COUNT(*) <> 1
ORDER BY n_rows DESC, opinion_id
LIMIT 100;


/*
===============================================================================
2. Confirm that multiple opinions per CourtListener docket are preserved
===============================================================================
*/

DROP TABLE IF EXISTS tmp_cl_docket_opinion_validation;

CREATE TEMP TABLE tmp_cl_docket_opinion_validation AS
SELECT
    docket_id,
    COUNT(DISTINCT opinion_id) AS n_opinions,
    COUNT(DISTINCT cluster_id) AS n_clusters,
    COUNT(DISTINCT court_id) AS n_courts,
    COUNT(DISTINCT fjc_docket_candidate)
        FILTER (WHERE fjc_docket_candidate IS NOT NULL) AS n_parsed_docket_candidates,
    COUNT(DISTINCT selected_fjc_appeal_id)
        FILTER (WHERE selected_fjc_appeal_id IS NOT NULL) AS n_selected_fjc_appeals,
    COUNT(*) FILTER (WHERE selected_fjc_appeal_id IS NOT NULL)
        AS n_matched_opinions,
    COUNT(*) FILTER (WHERE selected_fjc_appeal_id IS NULL)
        AS n_unmatched_opinions,
    MIN(opinion_date) AS first_opinion_date,
    MAX(opinion_date) AS last_opinion_date,
    MAX(opinion_date) - MIN(opinion_date) AS opinion_date_span_days
FROM tmp_fjc_opinion_final_match
GROUP BY docket_id;

ANALYZE tmp_cl_docket_opinion_validation;

SELECT
    COUNT(*) AS n_dockets,
    COUNT(*) FILTER (WHERE n_opinions > 1) AS n_dockets_with_multiple_opinions,
    SUM(n_opinions) FILTER (WHERE n_opinions > 1)
        AS n_opinions_in_multi_opinion_dockets,
    MAX(n_opinions) AS max_opinions_on_one_docket
FROM tmp_cl_docket_opinion_validation;

SELECT
    CASE
        WHEN n_opinions = 1 THEN '1'
        WHEN n_opinions BETWEEN 2 AND 3 THEN '2-3'
        WHEN n_opinions BETWEEN 4 AND 10 THEN '4-10'
        WHEN n_opinions BETWEEN 11 AND 25 THEN '11-25'
        ELSE '26+'
    END AS opinions_per_docket_bucket,
    COUNT(*) AS n_dockets,
    SUM(n_opinions) AS n_opinions
FROM tmp_cl_docket_opinion_validation
GROUP BY 1
ORDER BY
    CASE opinions_per_docket_bucket
        WHEN '1' THEN 1
        WHEN '2-3' THEN 2
        WHEN '4-10' THEN 3
        WHEN '11-25' THEN 4
        ELSE 5
    END;


/*
===============================================================================
3. Docket-level consistency

Expected:
- n_selected_fjc_appeals = 0: no selected match for this docket.
- n_selected_fjc_appeals = 1: desired one-docket-to-one-appeal relationship.
- n_selected_fjc_appeals > 1: conflict requiring investigation.

Multiple opinions are NOT an error. Multiple selected appeals for the same
CourtListener docket_id are the potential error.
===============================================================================
*/

SELECT
    CASE
        WHEN n_selected_fjc_appeals = 0 THEN 'no_selected_fjc_appeal'
        WHEN n_selected_fjc_appeals = 1 THEN 'one_selected_fjc_appeal'
        ELSE 'conflicting_multiple_fjc_appeals'
    END AS docket_mapping_status,
    COUNT(*) AS n_dockets,
    SUM(n_opinions) AS n_opinions
FROM tmp_cl_docket_opinion_validation
GROUP BY 1
ORDER BY 1;

SELECT
    docket_id,
    n_opinions,
    n_clusters,
    n_courts,
    n_parsed_docket_candidates,
    n_selected_fjc_appeals,
    n_matched_opinions,
    n_unmatched_opinions,
    first_opinion_date,
    last_opinion_date,
    opinion_date_span_days
FROM tmp_cl_docket_opinion_validation
WHERE n_selected_fjc_appeals > 1
ORDER BY n_selected_fjc_appeals DESC, n_opinions DESC, docket_id
LIMIT 200;


/*
===============================================================================
4. Detailed rows for conflicting CourtListener docket_ids
===============================================================================
*/

WITH conflicts AS (
    SELECT docket_id
    FROM tmp_cl_docket_opinion_validation
    WHERE n_selected_fjc_appeals > 1
)
SELECT
    m.docket_id,
    m.opinion_id,
    m.cluster_id,
    m.opinion_date,
    m.court_id,
    m.docket_number,
    m.fjc_docket_candidate,
    m.selected_fjc_appeal_id,
    m.final_match_status,
    m.final_confidence_tier,
    m.selected_fjc_judgment_date,
    m.selected_judgment_date_diff_days,
    m.selected_appellant,
    m.selected_appellee
FROM tmp_fjc_opinion_final_match m
JOIN conflicts c USING (docket_id)
ORDER BY
    m.docket_id,
    m.selected_fjc_appeal_id,
    m.opinion_date,
    m.opinion_id
LIMIT 1000;


/*
===============================================================================
5. Cluster-level consistency

A cluster can contain majority, concurrence, dissent, amended versions, etc.
Those individual opinions should normally resolve to the same FJC appeal.
===============================================================================
*/

DROP TABLE IF EXISTS tmp_cl_cluster_match_validation;

CREATE TEMP TABLE tmp_cl_cluster_match_validation AS
SELECT
    cluster_id,
    COUNT(DISTINCT opinion_id) AS n_opinions,
    COUNT(DISTINCT docket_id) AS n_dockets,
    COUNT(DISTINCT selected_fjc_appeal_id)
        FILTER (WHERE selected_fjc_appeal_id IS NOT NULL) AS n_selected_fjc_appeals,
    COUNT(*) FILTER (WHERE selected_fjc_appeal_id IS NOT NULL)
        AS n_matched_opinions,
    COUNT(*) FILTER (WHERE selected_fjc_appeal_id IS NULL)
        AS n_unmatched_opinions,
    MIN(opinion_date) AS first_opinion_date,
    MAX(opinion_date) AS last_opinion_date
FROM tmp_fjc_opinion_final_match
GROUP BY cluster_id;

ANALYZE tmp_cl_cluster_match_validation;

SELECT
    COUNT(*) FILTER (WHERE n_opinions > 1) AS n_multi_opinion_clusters,
    SUM(n_opinions) FILTER (WHERE n_opinions > 1)
        AS n_opinions_in_multi_opinion_clusters,
    COUNT(*) FILTER (WHERE n_selected_fjc_appeals > 1)
        AS n_clusters_with_conflicting_fjc_appeals
FROM tmp_cl_cluster_match_validation;

SELECT
    cluster_id,
    n_opinions,
    n_dockets,
    n_selected_fjc_appeals,
    n_matched_opinions,
    n_unmatched_opinions,
    first_opinion_date,
    last_opinion_date
FROM tmp_cl_cluster_match_validation
WHERE n_selected_fjc_appeals > 1
ORDER BY n_selected_fjc_appeals DESC, n_opinions DESC, cluster_id
LIMIT 200;


/*
===============================================================================
6. Normalized court+docket consistency

This directly tests the matching key. All CourtListener opinions carrying the
same court_id and parsed docket candidate should normally resolve to the same
FJC appeal. Multiple opinions are expected and retained.
===============================================================================
*/

DROP TABLE IF EXISTS tmp_normalized_docket_match_validation;

CREATE TEMP TABLE tmp_normalized_docket_match_validation AS
SELECT
    court_id,
    fjc_docket_candidate,
    COUNT(DISTINCT opinion_id) AS n_opinions,
    COUNT(DISTINCT docket_id) AS n_cl_dockets,
    COUNT(DISTINCT cluster_id) AS n_clusters,
    COUNT(DISTINCT selected_fjc_appeal_id)
        FILTER (WHERE selected_fjc_appeal_id IS NOT NULL) AS n_selected_fjc_appeals,
    COUNT(*) FILTER (WHERE selected_fjc_appeal_id IS NOT NULL)
        AS n_matched_opinions,
    COUNT(*) FILTER (WHERE selected_fjc_appeal_id IS NULL)
        AS n_unmatched_opinions,
    MIN(opinion_date) AS first_opinion_date,
    MAX(opinion_date) AS last_opinion_date,
    MAX(opinion_date) - MIN(opinion_date) AS opinion_date_span_days
FROM tmp_fjc_opinion_final_match
WHERE fjc_docket_candidate IS NOT NULL
GROUP BY court_id, fjc_docket_candidate;

ANALYZE tmp_normalized_docket_match_validation;

SELECT
    COUNT(*) AS n_normalized_court_dockets,
    COUNT(*) FILTER (WHERE n_opinions > 1)
        AS n_normalized_dockets_with_multiple_opinions,
    SUM(n_opinions) FILTER (WHERE n_opinions > 1)
        AS n_opinions_in_multi_opinion_normalized_dockets,
    COUNT(*) FILTER (WHERE n_selected_fjc_appeals > 1)
        AS n_normalized_dockets_with_conflicting_selected_appeals
FROM tmp_normalized_docket_match_validation;

SELECT
    court_id,
    fjc_docket_candidate,
    n_opinions,
    n_cl_dockets,
    n_clusters,
    n_selected_fjc_appeals,
    n_matched_opinions,
    n_unmatched_opinions,
    first_opinion_date,
    last_opinion_date,
    opinion_date_span_days
FROM tmp_normalized_docket_match_validation
WHERE n_selected_fjc_appeals > 1
ORDER BY n_selected_fjc_appeals DESC, n_opinions DESC
LIMIT 200;


/*
===============================================================================
7. One FJC appeal linked to multiple CourtListener opinions

This is expected. The diagnostics below distinguish plausible multiple-opinion
linkage from suspicious over-linkage.
===============================================================================
*/

DROP TABLE IF EXISTS tmp_fjc_appeal_opinion_validation;

CREATE TEMP TABLE tmp_fjc_appeal_opinion_validation AS
SELECT
    selected_fjc_appeal_id,
    COUNT(DISTINCT opinion_id) AS n_opinions,
    COUNT(DISTINCT docket_id) AS n_cl_dockets,
    COUNT(DISTINCT cluster_id) AS n_clusters,
    COUNT(DISTINCT court_id) AS n_courts,
    COUNT(DISTINCT fjc_docket_candidate) AS n_normalized_dockets,
    COUNT(DISTINCT final_confidence_tier) AS n_confidence_tiers,
    MIN(opinion_date) AS first_opinion_date,
    MAX(opinion_date) AS last_opinion_date,
    MAX(opinion_date) - MIN(opinion_date) AS opinion_date_span_days,
    MIN(selected_fjc_judgment_date) AS min_fjc_judgment_date,
    MAX(selected_fjc_judgment_date) AS max_fjc_judgment_date
FROM tmp_fjc_opinion_final_match
WHERE selected_fjc_appeal_id IS NOT NULL
GROUP BY selected_fjc_appeal_id;

ANALYZE tmp_fjc_appeal_opinion_validation;

SELECT
    CASE
        WHEN n_opinions = 1 THEN '1'
        WHEN n_opinions BETWEEN 2 AND 3 THEN '2-3'
        WHEN n_opinions BETWEEN 4 AND 10 THEN '4-10'
        WHEN n_opinions BETWEEN 11 AND 25 THEN '11-25'
        ELSE '26+'
    END AS opinions_per_fjc_appeal_bucket,
    COUNT(*) AS n_fjc_appeals,
    SUM(n_opinions) AS n_opinions
FROM tmp_fjc_appeal_opinion_validation
GROUP BY 1
ORDER BY
    CASE opinions_per_fjc_appeal_bucket
        WHEN '1' THEN 1
        WHEN '2-3' THEN 2
        WHEN '4-10' THEN 3
        WHEN '11-25' THEN 4
        ELSE 5
    END;

/* Suspicious only; not automatic errors. */
SELECT
    selected_fjc_appeal_id,
    n_opinions,
    n_cl_dockets,
    n_clusters,
    n_courts,
    n_normalized_dockets,
    n_confidence_tiers,
    first_opinion_date,
    last_opinion_date,
    opinion_date_span_days,
    min_fjc_judgment_date,
    max_fjc_judgment_date
FROM tmp_fjc_appeal_opinion_validation
WHERE n_courts > 1
   OR n_normalized_dockets > 1
   OR n_cl_dockets > 5
   OR n_clusters > 10
   OR opinion_date_span_days > 3650
ORDER BY
    n_courts DESC,
    n_normalized_dockets DESC,
    n_clusters DESC,
    n_opinions DESC
LIMIT 300;


/*
===============================================================================
8. Mixed-match status within the same CourtListener docket

A docket where some opinions match and others do not may be legitimate when
some documents have malformed metadata, but it deserves review.
===============================================================================
*/

SELECT
    COUNT(*) AS n_dockets_with_mixed_matched_and_unmatched_opinions,
    SUM(n_opinions) AS n_opinions_in_those_dockets
FROM tmp_cl_docket_opinion_validation
WHERE n_matched_opinions > 0
  AND n_unmatched_opinions > 0;

SELECT
    docket_id,
    n_opinions,
    n_clusters,
    n_selected_fjc_appeals,
    n_matched_opinions,
    n_unmatched_opinions,
    first_opinion_date,
    last_opinion_date
FROM tmp_cl_docket_opinion_validation
WHERE n_matched_opinions > 0
  AND n_unmatched_opinions > 0
ORDER BY n_unmatched_opinions DESC, n_opinions DESC
LIMIT 200;


/*
===============================================================================
9. Judgment-date behavior for multiple opinions on one FJC appeal

Multiple opinion documents can share the exact judgment date. Amended or
rehearing documents may differ. Large spreads are review candidates, not
automatic failures.
===============================================================================
*/

WITH multi_opinion_appeals AS (
    SELECT selected_fjc_appeal_id
    FROM tmp_fjc_appeal_opinion_validation
    WHERE n_opinions > 1
)
SELECT
    CASE
        WHEN v.opinion_date_span_days = 0 THEN 'same_day'
        WHEN v.opinion_date_span_days BETWEEN 1 AND 7 THEN '1-7_days'
        WHEN v.opinion_date_span_days BETWEEN 8 AND 30 THEN '8-30_days'
        WHEN v.opinion_date_span_days BETWEEN 31 AND 365 THEN '31-365_days'
        WHEN v.opinion_date_span_days BETWEEN 366 AND 3650 THEN '1-10_years'
        ELSE 'over_10_years'
    END AS opinion_date_span_bucket,
    COUNT(*) AS n_fjc_appeals,
    SUM(v.n_opinions) AS n_opinions
FROM tmp_fjc_appeal_opinion_validation v
JOIN multi_opinion_appeals m USING (selected_fjc_appeal_id)
GROUP BY 1
ORDER BY
    CASE opinion_date_span_bucket
        WHEN 'same_day' THEN 1
        WHEN '1-7_days' THEN 2
        WHEN '8-30_days' THEN 3
        WHEN '31-365_days' THEN 4
        WHEN '1-10_years' THEN 5
        ELSE 6
    END;


/*
===============================================================================
10. Negative controls

A. Wrong-circuit control:
   Rotate each parsed CourtListener court to another circuit while keeping the
   docket number unchanged. Correct matching should collapse sharply.

B. Shifted-year control:
   Add one to the two-digit docket year while keeping court and sequence.
   Again, matches should collapse sharply.

These estimate accidental key-collision rates. They do not alter real data.
===============================================================================
*/

DROP TABLE IF EXISTS tmp_fjc_distinct_match_keys;

CREATE TEMP TABLE tmp_fjc_distinct_match_keys AS
SELECT DISTINCT
    f.court_id,
    LPAD(f.fjc_docket_raw, 7, '0') AS normalized_fjc_docket
FROM ext.fjc_appellate_normalized f
WHERE f.fjc_docket_raw IS NOT NULL;

CREATE INDEX ON tmp_fjc_distinct_match_keys (court_id, normalized_fjc_docket);
ANALYZE tmp_fjc_distinct_match_keys;

WITH parsed AS (
    SELECT DISTINCT
        opinion_id,
        court_id,
        fjc_docket_candidate
    FROM tmp_fjc_opinion_final_match
    WHERE opinion_date >= DATE '1971-01-01'
      AND fjc_docket_candidate ~ '^[0-9]{7}$'
),
wrong_circuit AS (
    SELECT
        p.*,
        CASE p.court_id
            WHEN 'cadc' THEN 'ca1'
            WHEN 'ca1'  THEN 'ca2'
            WHEN 'ca2'  THEN 'ca3'
            WHEN 'ca3'  THEN 'ca4'
            WHEN 'ca4'  THEN 'ca5'
            WHEN 'ca5'  THEN 'ca6'
            WHEN 'ca6'  THEN 'ca7'
            WHEN 'ca7'  THEN 'ca8'
            WHEN 'ca8'  THEN 'ca9'
            WHEN 'ca9'  THEN 'ca10'
            WHEN 'ca10' THEN 'ca11'
            WHEN 'ca11' THEN 'cadc'
        END AS control_court_id
    FROM parsed p
),
shifted_year AS (
    SELECT
        p.*,
        LPAD((((SUBSTRING(p.fjc_docket_candidate, 1, 2)::int + 1) % 100))::text, 2, '0')
            || SUBSTRING(p.fjc_docket_candidate, 3, 5)
            AS control_docket
    FROM parsed p
)
SELECT
    (SELECT COUNT(*) FROM parsed) AS n_parseable_covered_opinions,

    (SELECT COUNT(*)
     FROM wrong_circuit w
     JOIN tmp_fjc_distinct_match_keys k
       ON k.court_id = w.control_court_id
      AND k.normalized_fjc_docket = w.fjc_docket_candidate
    ) AS n_wrong_circuit_control_matches,

    ROUND(
        100.0 *
        (SELECT COUNT(*)
         FROM wrong_circuit w
         JOIN tmp_fjc_distinct_match_keys k
           ON k.court_id = w.control_court_id
          AND k.normalized_fjc_docket = w.fjc_docket_candidate)
        / NULLIF((SELECT COUNT(*) FROM parsed), 0),
        4
    ) AS pct_wrong_circuit_control_matches,

    (SELECT COUNT(*)
     FROM shifted_year y
     JOIN tmp_fjc_distinct_match_keys k
       ON k.court_id = y.court_id
      AND k.normalized_fjc_docket = y.control_docket
    ) AS n_shifted_year_control_matches,

    ROUND(
        100.0 *
        (SELECT COUNT(*)
         FROM shifted_year y
         JOIN tmp_fjc_distinct_match_keys k
           ON k.court_id = y.court_id
          AND k.normalized_fjc_docket = y.control_docket)
        / NULLIF((SELECT COUNT(*) FROM parsed), 0),
        4
    ) AS pct_shifted_year_control_matches;


/*
===============================================================================
11. Deterministic review sample: multi-opinion dockets mapped consistently
===============================================================================
*/

WITH sampled_dockets AS (
    SELECT docket_id
    FROM tmp_cl_docket_opinion_validation
    WHERE n_opinions > 1
      AND n_selected_fjc_appeals = 1
    ORDER BY MD5(docket_id::text)
    LIMIT 50
)
SELECT
    m.docket_id,
    m.opinion_id,
    m.cluster_id,
    m.opinion_date,
    m.court_id,
    m.docket_number,
    m.fjc_docket_candidate,
    m.selected_fjc_appeal_id,
    m.final_match_status,
    m.final_confidence_tier,
    m.selected_fjc_judgment_date,
    m.selected_judgment_date_diff_days,
    m.selected_appellant,
    m.selected_appellee
FROM tmp_fjc_opinion_final_match m
JOIN sampled_dockets s USING (docket_id)
ORDER BY m.docket_id, m.opinion_date, m.opinion_id;


/*
===============================================================================
12. Deterministic review sample: suspicious conflicts
===============================================================================
*/

WITH suspicious AS (
    SELECT docket_id
    FROM tmp_cl_docket_opinion_validation
    WHERE n_selected_fjc_appeals > 1
       OR (n_matched_opinions > 0 AND n_unmatched_opinions > 0)
    ORDER BY MD5(docket_id::text)
    LIMIT 50
)
SELECT
    m.docket_id,
    m.opinion_id,
    m.cluster_id,
    m.opinion_date,
    m.court_id,
    m.docket_number,
    m.fjc_docket_candidate,
    m.selected_fjc_appeal_id,
    m.final_match_status,
    m.final_confidence_tier,
    m.selected_fjc_judgment_date,
    m.selected_judgment_date_diff_days,
    m.selected_appellant,
    m.selected_appellee
FROM tmp_fjc_opinion_final_match m
JOIN suspicious s USING (docket_id)
ORDER BY m.docket_id, m.selected_fjc_appeal_id, m.opinion_date, m.opinion_id;


/*
===============================================================================
13. Final integrity summary
===============================================================================
*/

SELECT
    (SELECT COUNT(*) - COUNT(DISTINCT opinion_id)
     FROM tmp_fjc_opinion_final_match)
        AS duplicate_final_rows_per_opinion,

    (SELECT COUNT(*)
     FROM tmp_cl_docket_opinion_validation
     WHERE n_opinions > 1)
        AS multi_opinion_dockets_preserved,

    (SELECT COUNT(*)
     FROM tmp_cl_docket_opinion_validation
     WHERE n_selected_fjc_appeals > 1)
        AS docket_ids_with_conflicting_selected_appeals,

    (SELECT COUNT(*)
     FROM tmp_cl_cluster_match_validation
     WHERE n_selected_fjc_appeals > 1)
        AS cluster_ids_with_conflicting_selected_appeals,

    (SELECT COUNT(*)
     FROM tmp_normalized_docket_match_validation
     WHERE n_selected_fjc_appeals > 1)
        AS normalized_dockets_with_conflicting_selected_appeals,

    (SELECT COUNT(*)
     FROM tmp_fjc_appeal_opinion_validation
     WHERE n_opinions > 1)
        AS fjc_appeals_with_multiple_opinions;

/* End of script. */
