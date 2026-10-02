/*
===============================================================================
14_analyze_fjc_duplicate_dockets_and_opinion_matches.sql
===============================================================================

Purpose
-------
Confirm that the linkage is performed at the individual CourtListener opinion
level and analyze FJC docket numbers that produce multiple candidate appeals.

This script builds on temporary tables created by:

    12_test_fjc_opinion_docket_matching.sql
    13_test_fjc_opinion_match_confidence.sql

Required temporary tables
-------------------------

    tmp_fjc_opinion_match_test
    tmp_fjc_match_confidence
    tmp_fjc_ambiguous_candidates

Main outputs
------------

    1. one-row-per-opinion validation
    2. duplicate FJC docket summary
    3. duplicate-group diagnostics
    4. a final candidate selection at the individual opinion level
    5. final match-status and confidence summaries
    6. checks that no opinion receives more than one selected FJC appeal
    7. review samples for unresolved or suspicious cases

Final selection rules
---------------------

Unique docket candidate:
    Select the sole FJC appeal. Confidence comes from script 13.

Multiple docket candidates:
    Select only when exactly one FJC candidate has the smallest absolute
    difference between CourtListener opinion_date and FJC judgment_date and
    that difference is at most 30 days.

Opinions before 1971:
    Reject, because they fall outside the FJC appellate coverage period.

No permanent tables are created.
===============================================================================
*/

\pset pager off
\timing on


/*
===============================================================================
1. Confirm that the source linkage table is at individual-opinion level
===============================================================================
*/

SELECT
    COUNT(*) AS n_rows,
    COUNT(DISTINCT opinion_id) AS n_distinct_opinions,
    COUNT(*) - COUNT(DISTINCT opinion_id) AS n_duplicate_opinion_rows,
    COUNT(DISTINCT cluster_id) AS n_distinct_clusters,
    COUNT(DISTINCT docket_id) AS n_distinct_dockets
FROM tmp_fjc_opinion_match_test;

/* Opinions that share a cluster but are still distinct opinion records. */
SELECT
    COUNT(*) AS n_clusters_with_multiple_opinions,
    SUM(n_opinions) AS n_opinions_in_multi_opinion_clusters
FROM (
    SELECT
        cluster_id,
        COUNT(DISTINCT opinion_id) AS n_opinions
    FROM tmp_fjc_opinion_match_test
    GROUP BY cluster_id
    HAVING COUNT(DISTINCT opinion_id) > 1
) s;


/*
===============================================================================
2. Build normalized FJC docket groups
===============================================================================
*/

DROP TABLE IF EXISTS tmp_fjc_duplicate_docket_groups;

CREATE TEMP TABLE tmp_fjc_duplicate_docket_groups AS
WITH fjc_parsed AS (
    SELECT
        f.fjc_appeal_id,
        f.court_id,
        LPAD(f.fjc_docket_raw, 7, '0') AS normalized_fjc_docket,
        f.fjc_docket_raw,
        f.source_period,

        CASE
            WHEN f.docket_date_raw ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN TO_DATE(f.docket_date_raw, 'MM/DD/YYYY')
        END AS fjc_docket_date,

        CASE
            WHEN f.judgment_date_raw ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN TO_DATE(f.judgment_date_raw, 'MM/DD/YYYY')
        END AS fjc_judgment_date,

        NULLIF(BTRIM(f.appellant), '') AS appellant,
        NULLIF(BTRIM(f.appellee), '') AS appellee,
        f.disposition_code,
        f.outcome_code
    FROM ext.fjc_appellate_normalized f
),
grouped AS (
    SELECT
        court_id,
        normalized_fjc_docket,
        COUNT(*) AS n_fjc_rows,
        COUNT(DISTINCT fjc_appeal_id) AS n_distinct_fjc_appeals,
        COUNT(DISTINCT fjc_docket_date) AS n_distinct_docket_dates,
        COUNT(DISTINCT fjc_judgment_date) AS n_distinct_judgment_dates,
        COUNT(DISTINCT appellant) AS n_distinct_appellants,
        COUNT(DISTINCT appellee) AS n_distinct_appellees,
        COUNT(DISTINCT disposition_code) AS n_distinct_dispositions,
        COUNT(DISTINCT outcome_code) AS n_distinct_outcomes,
        MIN(fjc_docket_date) AS min_fjc_docket_date,
        MAX(fjc_docket_date) AS max_fjc_docket_date,
        MIN(fjc_judgment_date) AS min_fjc_judgment_date,
        MAX(fjc_judgment_date) AS max_fjc_judgment_date
    FROM fjc_parsed
    GROUP BY court_id, normalized_fjc_docket
)
SELECT
    *,
    CASE
        WHEN n_distinct_fjc_appeals = 1
            THEN 'single_fjc_appeal'
        WHEN n_distinct_fjc_appeals > 1
         AND n_distinct_appellants <= 1
         AND n_distinct_appellees <= 1
            THEN 'multiple_rows_same_parties'
        WHEN n_distinct_fjc_appeals > 1
            THEN 'multiple_rows_different_or_missing_parties'
        ELSE 'unclassified'
    END AS duplicate_group_type
FROM grouped;

ANALYZE tmp_fjc_duplicate_docket_groups;


/*
===============================================================================
3. Overall duplicate-docket distribution in the FJC data
===============================================================================
*/

SELECT
    n_distinct_fjc_appeals AS n_fjc_candidates,
    COUNT(*) AS n_court_docket_groups
FROM tmp_fjc_duplicate_docket_groups
GROUP BY n_distinct_fjc_appeals
ORDER BY n_distinct_fjc_appeals;

SELECT
    duplicate_group_type,
    COUNT(*) AS n_court_docket_groups,
    SUM(n_distinct_fjc_appeals) AS n_fjc_appeals
FROM tmp_fjc_duplicate_docket_groups
WHERE n_distinct_fjc_appeals > 1
GROUP BY duplicate_group_type
ORDER BY duplicate_group_type;


/*
===============================================================================
4. Duplicate FJC dockets actually encountered by CourtListener opinions
===============================================================================
*/

WITH encountered AS (
    SELECT DISTINCT
        m.court_id,
        m.fjc_docket_candidate AS normalized_fjc_docket
    FROM tmp_fjc_opinion_match_test m
    WHERE m.fjc_docket_candidate IS NOT NULL
)
SELECT
    g.n_distinct_fjc_appeals AS n_fjc_candidates,
    COUNT(*) AS n_encountered_court_docket_groups
FROM encountered e
JOIN tmp_fjc_duplicate_docket_groups g
  ON g.court_id = e.court_id
 AND g.normalized_fjc_docket = e.normalized_fjc_docket
GROUP BY g.n_distinct_fjc_appeals
ORDER BY g.n_distinct_fjc_appeals;


/*
===============================================================================
5. Build one selected FJC match per individual CourtListener opinion
===============================================================================
*/

DROP TABLE IF EXISTS tmp_fjc_opinion_final_match;

CREATE TEMP TABLE tmp_fjc_opinion_final_match AS
WITH ambiguous_best AS (
    SELECT
        a.opinion_id,
        a.fjc_appeal_id,
        a.fjc_docket_date,
        a.fjc_judgment_date,
        a.judgment_date_diff_days,
        a.source_period,
        a.disposition_code,
        a.outcome_code,
        a.appellant,
        a.appellee,
        a.ambiguous_resolution_status
    FROM tmp_fjc_ambiguous_candidates a
    WHERE a.date_rank = 1
      AND a.n_candidates_tied_for_best_date = 1
      AND a.judgment_date_diff_days <= 30
),
base AS (
    SELECT
        c.opinion_id,
        c.cluster_id,
        c.docket_id,
        c.opinion_date,
        c.court_id,
        c.docket_number,
        c.fjc_docket_candidate,
        c.n_fjc_candidates,
        c.match_status AS original_match_status,
        c.confidence_tier AS original_confidence_tier,

        CASE
            WHEN c.opinion_date < DATE '1971-01-01'
                THEN NULL
            WHEN c.match_status = 'unique_match'
                THEN c.fjc_appeal_id
            WHEN c.match_status = 'ambiguous_match'
                THEN ab.fjc_appeal_id
        END AS selected_fjc_appeal_id,

        CASE
            WHEN c.opinion_date < DATE '1971-01-01'
                THEN 'rejected_before_1971'
            WHEN c.match_status = 'unique_match'
                THEN 'selected_unique_docket'
            WHEN c.match_status = 'ambiguous_match'
             AND ab.fjc_appeal_id IS NOT NULL
                THEN 'selected_unique_best_date'
            WHEN c.match_status = 'ambiguous_match'
                THEN 'unresolved_ambiguous'
            WHEN c.match_status = 'no_match'
                THEN 'no_match'
            WHEN c.match_status = 'not_parseable'
                THEN 'not_parseable'
            ELSE 'unclassified'
        END AS final_match_status,

        CASE
            WHEN c.opinion_date < DATE '1971-01-01'
                THEN 'rejected_before_1971'
            WHEN c.match_status = 'unique_match'
                THEN c.confidence_tier
            WHEN ab.ambiguous_resolution_status = 'resolved_exact_date'
                THEN 'tier_a_exact_date_ambiguous_resolved'
            WHEN ab.ambiguous_resolution_status = 'resolved_within_7_days'
                THEN 'tier_b_within_7_days_ambiguous_resolved'
            WHEN ab.ambiguous_resolution_status = 'resolved_within_30_days'
                THEN 'tier_c_within_30_days_ambiguous_resolved'
            WHEN c.match_status = 'ambiguous_match'
                THEN 'unresolved_ambiguous'
            WHEN c.match_status = 'no_match'
                THEN 'no_match'
            WHEN c.match_status = 'not_parseable'
                THEN 'not_parseable'
            ELSE 'unclassified'
        END AS final_confidence_tier,

        COALESCE(ab.fjc_docket_date, c.fjc_docket_date) AS selected_fjc_docket_date,
        COALESCE(ab.fjc_judgment_date, c.fjc_judgment_date) AS selected_fjc_judgment_date,
        COALESCE(ab.judgment_date_diff_days, c.judgment_date_diff_days)
            AS selected_judgment_date_diff_days,
        COALESCE(ab.source_period, c.source_period) AS selected_source_period,
        COALESCE(ab.disposition_code, c.disposition_code) AS selected_disposition_code,
        COALESCE(ab.outcome_code, c.outcome_code) AS selected_outcome_code,
        COALESCE(ab.appellant, c.appellant) AS selected_appellant,
        COALESCE(ab.appellee, c.appellee) AS selected_appellee

    FROM tmp_fjc_match_confidence c
    LEFT JOIN ambiguous_best ab
      ON ab.opinion_id = c.opinion_id
)
SELECT *
FROM base;

ANALYZE tmp_fjc_opinion_final_match;


/*
===============================================================================
6. Validate exactly one row per individual opinion
===============================================================================
*/

SELECT
    COUNT(*) AS n_rows,
    COUNT(DISTINCT opinion_id) AS n_distinct_opinions,
    COUNT(*) - COUNT(DISTINCT opinion_id) AS n_duplicate_opinion_rows
FROM tmp_fjc_opinion_final_match;

SELECT
    opinion_id,
    COUNT(*) AS n_rows
FROM tmp_fjc_opinion_final_match
GROUP BY opinion_id
HAVING COUNT(*) > 1
ORDER BY n_rows DESC, opinion_id
LIMIT 100;


/*
===============================================================================
7. Final opinion-level match summary
===============================================================================
*/

SELECT
    final_match_status,
    COUNT(*) AS n_opinions,
    ROUND(
        100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0),
        2
    ) AS pct_all_opinions
FROM tmp_fjc_opinion_final_match
GROUP BY final_match_status
ORDER BY
    CASE final_match_status
        WHEN 'selected_unique_docket' THEN 1
        WHEN 'selected_unique_best_date' THEN 2
        WHEN 'unresolved_ambiguous' THEN 3
        WHEN 'no_match' THEN 4
        WHEN 'not_parseable' THEN 5
        WHEN 'rejected_before_1971' THEN 6
        ELSE 7
    END;

SELECT
    final_confidence_tier,
    COUNT(*) AS n_opinions
FROM tmp_fjc_opinion_final_match
GROUP BY final_confidence_tier
ORDER BY
    CASE final_confidence_tier
        WHEN 'tier_a_exact_date' THEN 1
        WHEN 'tier_a_exact_date_ambiguous_resolved' THEN 2
        WHEN 'tier_b_within_7_days' THEN 3
        WHEN 'tier_b_within_7_days_ambiguous_resolved' THEN 4
        WHEN 'tier_c_within_30_days' THEN 5
        WHEN 'tier_c_within_30_days_ambiguous_resolved' THEN 6
        WHEN 'review_over_30_days' THEN 7
        WHEN 'review_missing_date' THEN 8
        WHEN 'unresolved_ambiguous' THEN 9
        WHEN 'no_match' THEN 10
        WHEN 'not_parseable' THEN 11
        WHEN 'rejected_before_1971' THEN 12
        ELSE 13
    END;


/*
===============================================================================
8. Accepted opinion-level matches in the FJC-covered period
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE opinion_date >= DATE '1971-01-01'
    ) AS n_opinions_covered_period,

    COUNT(*) FILTER (
        WHERE selected_fjc_appeal_id IS NOT NULL
    ) AS n_opinions_with_selected_fjc_appeal,

    COUNT(*) FILTER (
        WHERE final_confidence_tier IN (
            'tier_a_exact_date',
            'tier_a_exact_date_ambiguous_resolved',
            'tier_b_within_7_days',
            'tier_b_within_7_days_ambiguous_resolved',
            'tier_c_within_30_days',
            'tier_c_within_30_days_ambiguous_resolved'
        )
    ) AS n_high_confidence_within_30_days,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE selected_fjc_appeal_id IS NOT NULL
        ) / NULLIF(COUNT(*) FILTER (
            WHERE opinion_date >= DATE '1971-01-01'
        ), 0),
        2
    ) AS pct_covered_period_with_selected_fjc_appeal,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE final_confidence_tier IN (
                'tier_a_exact_date',
                'tier_a_exact_date_ambiguous_resolved',
                'tier_b_within_7_days',
                'tier_b_within_7_days_ambiguous_resolved',
                'tier_c_within_30_days',
                'tier_c_within_30_days_ambiguous_resolved'
            )
        ) / NULLIF(COUNT(*) FILTER (
            WHERE opinion_date >= DATE '1971-01-01'
        ), 0),
        2
    ) AS pct_covered_period_high_confidence_within_30_days

FROM tmp_fjc_opinion_final_match;


/*
===============================================================================
9. How many individual opinions map to the same FJC appeal?

This is not automatically an error: one appeal can have multiple opinions,
amended opinions, rehearing opinions, or separate documents in CourtListener.
===============================================================================
*/

WITH appeal_usage AS (
    SELECT
        selected_fjc_appeal_id,
        COUNT(DISTINCT opinion_id) AS n_opinions,
        COUNT(DISTINCT cluster_id) AS n_clusters,
        MIN(opinion_date) AS first_opinion_date,
        MAX(opinion_date) AS last_opinion_date
    FROM tmp_fjc_opinion_final_match
    WHERE selected_fjc_appeal_id IS NOT NULL
    GROUP BY selected_fjc_appeal_id
)
SELECT
    n_opinions,
    COUNT(*) AS n_fjc_appeals
FROM appeal_usage
GROUP BY n_opinions
ORDER BY n_opinions;


/*
===============================================================================
10. Sample FJC appeals linked to multiple individual opinions
===============================================================================
*/

WITH multi AS (
    SELECT
        selected_fjc_appeal_id
    FROM tmp_fjc_opinion_final_match
    WHERE selected_fjc_appeal_id IS NOT NULL
    GROUP BY selected_fjc_appeal_id
    HAVING COUNT(DISTINCT opinion_id) > 1
    ORDER BY COUNT(DISTINCT opinion_id) DESC, selected_fjc_appeal_id
    LIMIT 50
)
SELECT
    m.selected_fjc_appeal_id,
    m.opinion_id,
    m.cluster_id,
    m.docket_id,
    m.opinion_date,
    m.court_id,
    m.docket_number,
    m.final_match_status,
    m.final_confidence_tier,
    m.selected_fjc_judgment_date,
    m.selected_judgment_date_diff_days,
    m.selected_appellant,
    m.selected_appellee
FROM tmp_fjc_opinion_final_match m
JOIN multi x
  ON x.selected_fjc_appeal_id = m.selected_fjc_appeal_id
ORDER BY
    m.selected_fjc_appeal_id,
    m.opinion_date,
    m.opinion_id;


/*
===============================================================================
11. Sample duplicate FJC docket groups with candidate details
===============================================================================
*/

WITH sampled_groups AS (
    SELECT
        court_id,
        normalized_fjc_docket
    FROM tmp_fjc_duplicate_docket_groups
    WHERE n_distinct_fjc_appeals > 1
    ORDER BY n_distinct_fjc_appeals DESC, court_id, normalized_fjc_docket
    LIMIT 100
)
SELECT
    f.court_id,
    LPAD(f.fjc_docket_raw, 7, '0') AS normalized_fjc_docket,
    f.fjc_appeal_id,
    f.docket_date_raw,
    f.judgment_date_raw,
    f.source_period,
    f.disposition_code,
    f.outcome_code,
    f.appellant,
    f.appellee
FROM ext.fjc_appellate_normalized f
JOIN sampled_groups s
  ON s.court_id = f.court_id
 AND s.normalized_fjc_docket = LPAD(f.fjc_docket_raw, 7, '0')
ORDER BY
    f.court_id,
    normalized_fjc_docket,
    f.judgment_date_raw,
    f.fjc_appeal_id;


/*
===============================================================================
12. Sample unresolved ambiguous opinions
===============================================================================
*/

SELECT
    opinion_id,
    cluster_id,
    docket_id,
    opinion_date,
    court_id,
    docket_number,
    fjc_docket_candidate,
    n_fjc_candidates,
    final_match_status,
    final_confidence_tier
FROM tmp_fjc_opinion_final_match
WHERE final_match_status = 'unresolved_ambiguous'
ORDER BY RANDOM()
LIMIT 100;


/*
===============================================================================
13. Candidate details for a random sample of unresolved opinions
===============================================================================
*/

WITH sampled AS (
    SELECT opinion_id
    FROM tmp_fjc_opinion_final_match
    WHERE final_match_status = 'unresolved_ambiguous'
    ORDER BY RANDOM()
    LIMIT 50
)
SELECT
    a.opinion_id,
    a.cluster_id,
    a.docket_id,
    a.opinion_date,
    a.court_id,
    a.docket_number,
    a.fjc_docket_candidate,
    a.n_fjc_candidates,
    a.fjc_appeal_id,
    a.fjc_docket_date,
    a.fjc_judgment_date,
    a.judgment_date_diff_days,
    a.date_rank,
    a.n_candidates_tied_for_best_date,
    a.ambiguous_resolution_status,
    a.appellant,
    a.appellee
FROM tmp_fjc_ambiguous_candidates a
JOIN sampled s
  ON s.opinion_id = a.opinion_id
ORDER BY
    a.opinion_id,
    a.date_rank,
    a.fjc_appeal_id;


/*
===============================================================================
14. Final integrity checks
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE opinion_date < DATE '1971-01-01'
          AND selected_fjc_appeal_id IS NOT NULL
    ) AS invalid_pre1971_selected_matches,

    COUNT(*) FILTER (
        WHERE final_match_status = 'selected_unique_best_date'
          AND selected_judgment_date_diff_days > 30
    ) AS invalid_ambiguous_selected_over_30_days,

    COUNT(*) FILTER (
        WHERE final_match_status IN (
            'selected_unique_docket',
            'selected_unique_best_date'
        )
          AND selected_fjc_appeal_id IS NULL
    ) AS invalid_selected_status_without_fjc_id,

    COUNT(*) FILTER (
        WHERE final_match_status NOT IN (
            'selected_unique_docket',
            'selected_unique_best_date'
        )
          AND selected_fjc_appeal_id IS NOT NULL
    ) AS invalid_unselected_status_with_fjc_id
FROM tmp_fjc_opinion_final_match;

/* End of script. */
