/*
===============================================================================
13_test_fjc_opinion_match_confidence.sql
===============================================================================

Purpose
-------
Evaluate confidence levels for CourtListener-to-FJC appellate opinion matches.

This script builds on the temporary table created by:

    12_test_fjc_opinion_docket_matching.sql

Required temporary table
------------------------

    tmp_fjc_opinion_match_test

The script:

    1. excludes opinions before the FJC coverage period
    2. parses FJC docket and judgment dates
    3. calculates date differences
    4. assigns confidence tiers to unique docket matches
    5. evaluates ambiguous docket matches using judgment-date proximity
    6. identifies uniquely best ambiguous candidates
    7. reports counts by period and court
    8. provides review samples

Confidence tiers for unique docket matches
-------------------------------------------

    tier_a_exact_date
        Unique circuit+docket match and exact judgment-date agreement.

    tier_b_within_7_days
        Unique circuit+docket match and absolute date difference <= 7 days.

    tier_c_within_30_days
        Unique circuit+docket match and absolute date difference <= 30 days.

    review_over_30_days
        Unique circuit+docket match but date difference > 30 days.

    review_missing_date
        Unique circuit+docket match but one of the dates is unavailable.

Ambiguous matches
-----------------

For opinions with multiple FJC candidates, the script ranks candidates by the
absolute difference between CourtListener opinion_date and FJC judgment_date.

An ambiguous match is considered date-resolvable only when:

    - exactly one candidate has the smallest date difference
    - the smallest date difference is <= 30 days

No permanent tables are created.
===============================================================================
*/

\pset pager off
\timing on


/*
===============================================================================
1. Create parsed FJC date base
===============================================================================
*/

DROP TABLE IF EXISTS tmp_fjc_match_confidence;

CREATE TEMP TABLE tmp_fjc_match_confidence AS
WITH fjc_dates AS (
    SELECT
        f.*,

        CASE
            WHEN f.docket_date_raw ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN TO_DATE(f.docket_date_raw, 'MM/DD/YYYY')
        END AS fjc_docket_date,

        CASE
            WHEN f.judgment_date_raw ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN TO_DATE(f.judgment_date_raw, 'MM/DD/YYYY')
        END AS fjc_judgment_date

    FROM ext.fjc_appellate_normalized f
),
unique_matches AS (
    SELECT
        m.opinion_id,
        m.cluster_id,
        m.docket_id,
        m.opinion_date,
        m.court_id,
        m.docket_number,
        m.fjc_docket_candidate,
        m.n_fjc_candidates,
        m.match_status,
        m.fjc_appeal_id,

        f.source_period,
        f.fjc_docket_date,
        f.fjc_judgment_date,
        f.disposition_code,
        f.outcome_code,
        f.appellant,
        f.appellee,

        CASE
            WHEN m.opinion_date IS NOT NULL
             AND f.fjc_judgment_date IS NOT NULL
            THEN ABS(m.opinion_date - f.fjc_judgment_date)
        END AS judgment_date_diff_days

    FROM tmp_fjc_opinion_match_test m
    LEFT JOIN fjc_dates f
        ON f.fjc_appeal_id = m.fjc_appeal_id
)
SELECT
    um.*,

    CASE
        WHEN um.opinion_date < DATE '1971-01-01'
            THEN 'rejected_before_1971'

        WHEN um.match_status = 'not_parseable'
            THEN 'not_parseable'

        WHEN um.match_status = 'no_match'
            THEN 'no_match'

        WHEN um.match_status = 'ambiguous_match'
            THEN 'ambiguous_match'

        WHEN um.match_status = 'unique_match'
         AND um.judgment_date_diff_days = 0
            THEN 'tier_a_exact_date'

        WHEN um.match_status = 'unique_match'
         AND um.judgment_date_diff_days BETWEEN 1 AND 7
            THEN 'tier_b_within_7_days'

        WHEN um.match_status = 'unique_match'
         AND um.judgment_date_diff_days BETWEEN 8 AND 30
            THEN 'tier_c_within_30_days'

        WHEN um.match_status = 'unique_match'
         AND um.judgment_date_diff_days > 30
            THEN 'review_over_30_days'

        WHEN um.match_status = 'unique_match'
         AND um.judgment_date_diff_days IS NULL
            THEN 'review_missing_date'

        ELSE 'unclassified'
    END AS confidence_tier

FROM unique_matches um;

ANALYZE tmp_fjc_match_confidence;


/*
===============================================================================
2. Overall confidence-tier distribution
===============================================================================
*/

SELECT
    confidence_tier,
    COUNT(*) AS n_opinions,
    ROUND(
        100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0),
        2
    ) AS pct_all_opinions
FROM tmp_fjc_match_confidence
GROUP BY confidence_tier
ORDER BY
    CASE confidence_tier
        WHEN 'tier_a_exact_date' THEN 1
        WHEN 'tier_b_within_7_days' THEN 2
        WHEN 'tier_c_within_30_days' THEN 3
        WHEN 'review_over_30_days' THEN 4
        WHEN 'review_missing_date' THEN 5
        WHEN 'ambiguous_match' THEN 6
        WHEN 'no_match' THEN 7
        WHEN 'not_parseable' THEN 8
        WHEN 'rejected_before_1971' THEN 9
        ELSE 10
    END;


/*
===============================================================================
3. High-confidence coverage for the FJC-covered period
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE opinion_date >= DATE '1971-01-01'
    ) AS n_opinions_covered_period,

    COUNT(*) FILTER (
        WHERE confidence_tier = 'tier_a_exact_date'
    ) AS n_tier_a,

    COUNT(*) FILTER (
        WHERE confidence_tier IN (
            'tier_a_exact_date',
            'tier_b_within_7_days'
        )
    ) AS n_within_7_days,

    COUNT(*) FILTER (
        WHERE confidence_tier IN (
            'tier_a_exact_date',
            'tier_b_within_7_days',
            'tier_c_within_30_days'
        )
    ) AS n_within_30_days,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE confidence_tier = 'tier_a_exact_date'
        )
        / NULLIF(COUNT(*) FILTER (
            WHERE opinion_date >= DATE '1971-01-01'
        ), 0),
        2
    ) AS pct_tier_a_of_covered_period,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE confidence_tier IN (
                'tier_a_exact_date',
                'tier_b_within_7_days'
            )
        )
        / NULLIF(COUNT(*) FILTER (
            WHERE opinion_date >= DATE '1971-01-01'
        ), 0),
        2
    ) AS pct_within_7_days_of_covered_period,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE confidence_tier IN (
                'tier_a_exact_date',
                'tier_b_within_7_days',
                'tier_c_within_30_days'
            )
        )
        / NULLIF(COUNT(*) FILTER (
            WHERE opinion_date >= DATE '1971-01-01'
        ), 0),
        2
    ) AS pct_within_30_days_of_covered_period

FROM tmp_fjc_match_confidence;


/*
===============================================================================
4. Confidence tiers by period
===============================================================================
*/

WITH periodized AS (
    SELECT
        *,
        CASE
            WHEN opinion_date < DATE '1971-01-01'
                THEN 'before_1971'
            WHEN opinion_date < DATE '2008-01-01'
                THEN '1971to2007'
            ELSE '2008plus'
        END AS opinion_period,

        CASE
            WHEN opinion_date < DATE '1971-01-01' THEN 1
            WHEN opinion_date < DATE '2008-01-01' THEN 2
            ELSE 3
        END AS period_order

    FROM tmp_fjc_match_confidence
)
SELECT
    opinion_period,
    confidence_tier,
    COUNT(*) AS n_opinions
FROM periodized
GROUP BY opinion_period, period_order, confidence_tier
ORDER BY
    period_order,
    CASE confidence_tier
        WHEN 'tier_a_exact_date' THEN 1
        WHEN 'tier_b_within_7_days' THEN 2
        WHEN 'tier_c_within_30_days' THEN 3
        WHEN 'review_over_30_days' THEN 4
        WHEN 'review_missing_date' THEN 5
        WHEN 'ambiguous_match' THEN 6
        WHEN 'no_match' THEN 7
        WHEN 'not_parseable' THEN 8
        WHEN 'rejected_before_1971' THEN 9
        ELSE 10
    END;


/*
===============================================================================
5. Confidence tiers by court for covered period
===============================================================================
*/

SELECT
    court_id,
    COUNT(*) AS n_opinions,

    COUNT(*) FILTER (
        WHERE confidence_tier = 'tier_a_exact_date'
    ) AS n_tier_a,

    COUNT(*) FILTER (
        WHERE confidence_tier = 'tier_b_within_7_days'
    ) AS n_tier_b,

    COUNT(*) FILTER (
        WHERE confidence_tier = 'tier_c_within_30_days'
    ) AS n_tier_c,

    COUNT(*) FILTER (
        WHERE confidence_tier = 'review_over_30_days'
    ) AS n_review_over_30_days,

    COUNT(*) FILTER (
        WHERE confidence_tier = 'ambiguous_match'
    ) AS n_ambiguous,

    COUNT(*) FILTER (
        WHERE confidence_tier = 'no_match'
    ) AS n_no_match,

    COUNT(*) FILTER (
        WHERE confidence_tier = 'not_parseable'
    ) AS n_not_parseable,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE confidence_tier IN (
                'tier_a_exact_date',
                'tier_b_within_7_days',
                'tier_c_within_30_days'
            )
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_high_confidence_within_30_days

FROM tmp_fjc_match_confidence
WHERE opinion_date >= DATE '1971-01-01'
GROUP BY court_id
ORDER BY court_id;


/*
===============================================================================
6. Build candidate-level table for ambiguous matches
===============================================================================
*/

DROP TABLE IF EXISTS tmp_fjc_ambiguous_candidates;

CREATE TEMP TABLE tmp_fjc_ambiguous_candidates AS
WITH fjc_dates AS (
    SELECT
        f.*,

        CASE
            WHEN f.docket_date_raw ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN TO_DATE(f.docket_date_raw, 'MM/DD/YYYY')
        END AS fjc_docket_date,

        CASE
            WHEN f.judgment_date_raw ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN TO_DATE(f.judgment_date_raw, 'MM/DD/YYYY')
        END AS fjc_judgment_date

    FROM ext.fjc_appellate_normalized f
),
candidates AS (
    SELECT
        m.opinion_id,
        m.cluster_id,
        m.docket_id,
        m.opinion_date,
        m.court_id,
        m.docket_number,
        m.fjc_docket_candidate,
        m.n_fjc_candidates,

        f.fjc_appeal_id,
        f.source_period,
        f.fjc_docket_date,
        f.fjc_judgment_date,
        f.disposition_code,
        f.outcome_code,
        f.appellant,
        f.appellee,

        CASE
            WHEN m.opinion_date IS NOT NULL
             AND f.fjc_judgment_date IS NOT NULL
            THEN ABS(m.opinion_date - f.fjc_judgment_date)
        END AS judgment_date_diff_days

    FROM tmp_fjc_opinion_match_test m
    JOIN fjc_dates f
        ON f.court_id = m.court_id
       AND LPAD(f.fjc_docket_raw, 7, '0') = m.fjc_docket_candidate

    WHERE m.match_status = 'ambiguous_match'
      AND m.opinion_date >= DATE '1971-01-01'
),
ranked AS (
    SELECT
        c.*,

        DENSE_RANK() OVER (
            PARTITION BY c.opinion_id
            ORDER BY c.judgment_date_diff_days NULLS LAST
        ) AS date_rank,

        MIN(c.judgment_date_diff_days) OVER (
            PARTITION BY c.opinion_id
        ) AS min_judgment_date_diff_days

    FROM candidates c
),
best_tie_counts AS (
    SELECT
        r.*,

        COUNT(*) FILTER (
            WHERE r.date_rank = 1
        ) OVER (
            PARTITION BY r.opinion_id
        ) AS n_candidates_tied_for_best_date

    FROM ranked r
)
SELECT
    *,

    CASE
        WHEN date_rank = 1
         AND n_candidates_tied_for_best_date = 1
         AND judgment_date_diff_days = 0
            THEN 'resolved_exact_date'

        WHEN date_rank = 1
         AND n_candidates_tied_for_best_date = 1
         AND judgment_date_diff_days BETWEEN 1 AND 7
            THEN 'resolved_within_7_days'

        WHEN date_rank = 1
         AND n_candidates_tied_for_best_date = 1
         AND judgment_date_diff_days BETWEEN 8 AND 30
            THEN 'resolved_within_30_days'

        WHEN date_rank = 1
         AND n_candidates_tied_for_best_date = 1
         AND judgment_date_diff_days > 30
            THEN 'best_candidate_over_30_days'

        WHEN date_rank = 1
         AND n_candidates_tied_for_best_date > 1
            THEN 'tie_for_best_date'

        WHEN judgment_date_diff_days IS NULL
            THEN 'missing_judgment_date'

        ELSE 'non_best_candidate'
    END AS ambiguous_resolution_status

FROM best_tie_counts;

ANALYZE tmp_fjc_ambiguous_candidates;


/*
===============================================================================
7. Ambiguous-match resolution summary at opinion level
===============================================================================
*/

WITH opinion_resolution AS (
    SELECT
        opinion_id,
        MAX(n_fjc_candidates) AS n_fjc_candidates,
        MIN(min_judgment_date_diff_days) AS best_date_diff_days,
        MAX(n_candidates_tied_for_best_date) AS n_candidates_tied_for_best_date,

        CASE
            WHEN MAX(n_candidates_tied_for_best_date) = 1
             AND MIN(min_judgment_date_diff_days) = 0
                THEN 'resolved_exact_date'

            WHEN MAX(n_candidates_tied_for_best_date) = 1
             AND MIN(min_judgment_date_diff_days) BETWEEN 1 AND 7
                THEN 'resolved_within_7_days'

            WHEN MAX(n_candidates_tied_for_best_date) = 1
             AND MIN(min_judgment_date_diff_days) BETWEEN 8 AND 30
                THEN 'resolved_within_30_days'

            WHEN MAX(n_candidates_tied_for_best_date) = 1
             AND MIN(min_judgment_date_diff_days) > 30
                THEN 'best_candidate_over_30_days'

            WHEN MAX(n_candidates_tied_for_best_date) > 1
                THEN 'tie_for_best_date'

            ELSE 'missing_judgment_date'
        END AS opinion_resolution_status

    FROM tmp_fjc_ambiguous_candidates
    GROUP BY opinion_id
)
SELECT
    opinion_resolution_status,
    COUNT(*) AS n_opinions,
    ROUND(
        100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0),
        2
    ) AS pct_ambiguous_opinions
FROM opinion_resolution
GROUP BY opinion_resolution_status
ORDER BY
    CASE opinion_resolution_status
        WHEN 'resolved_exact_date' THEN 1
        WHEN 'resolved_within_7_days' THEN 2
        WHEN 'resolved_within_30_days' THEN 3
        WHEN 'best_candidate_over_30_days' THEN 4
        WHEN 'tie_for_best_date' THEN 5
        WHEN 'missing_judgment_date' THEN 6
        ELSE 7
    END;


/*
===============================================================================
8. Combined potential high-confidence coverage
===============================================================================
*/

WITH ambiguous_resolved AS (
    SELECT DISTINCT
        opinion_id,
        ambiguous_resolution_status
    FROM tmp_fjc_ambiguous_candidates
    WHERE date_rank = 1
      AND n_candidates_tied_for_best_date = 1
),
base AS (
    SELECT
        COUNT(*) FILTER (
            WHERE opinion_date >= DATE '1971-01-01'
        ) AS n_covered_period,

        COUNT(*) FILTER (
            WHERE confidence_tier IN (
                'tier_a_exact_date',
                'tier_b_within_7_days',
                'tier_c_within_30_days'
            )
        ) AS n_unique_within_30_days

    FROM tmp_fjc_match_confidence
),
ambiguous AS (
    SELECT
        COUNT(*) FILTER (
            WHERE ambiguous_resolution_status IN (
                'resolved_exact_date',
                'resolved_within_7_days',
                'resolved_within_30_days'
            )
        ) AS n_ambiguous_resolved_within_30_days
    FROM ambiguous_resolved
)
SELECT
    b.n_covered_period,
    b.n_unique_within_30_days,
    a.n_ambiguous_resolved_within_30_days,

    b.n_unique_within_30_days
        + a.n_ambiguous_resolved_within_30_days
        AS n_total_potential_high_confidence,

    ROUND(
        100.0 * (
            b.n_unique_within_30_days
            + a.n_ambiguous_resolved_within_30_days
        ) / NULLIF(b.n_covered_period, 0),
        2
    ) AS pct_total_potential_high_confidence

FROM base b
CROSS JOIN ambiguous a;


/*
===============================================================================
9. Sample unique matches requiring review
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
    fjc_appeal_id,
    fjc_docket_date,
    fjc_judgment_date,
    judgment_date_diff_days,
    disposition_code,
    outcome_code,
    appellant,
    appellee,
    confidence_tier
FROM tmp_fjc_match_confidence
WHERE confidence_tier = 'review_over_30_days'
ORDER BY judgment_date_diff_days DESC, opinion_id
LIMIT 200;


/*
===============================================================================
10. Sample ambiguous matches resolved by exact date
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
    fjc_appeal_id,
    fjc_docket_date,
    fjc_judgment_date,
    judgment_date_diff_days,
    disposition_code,
    outcome_code,
    appellant,
    appellee,
    ambiguous_resolution_status
FROM tmp_fjc_ambiguous_candidates
WHERE ambiguous_resolution_status = 'resolved_exact_date'
ORDER BY RANDOM()
LIMIT 200;


/*
===============================================================================
11. Sample ambiguous matches with ties for best date
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
    fjc_appeal_id,
    fjc_docket_date,
    fjc_judgment_date,
    judgment_date_diff_days,
    date_rank,
    n_candidates_tied_for_best_date,
    disposition_code,
    outcome_code,
    appellant,
    appellee
FROM tmp_fjc_ambiguous_candidates
WHERE ambiguous_resolution_status = 'tie_for_best_date'
ORDER BY opinion_id, fjc_appeal_id
LIMIT 200;


/*
===============================================================================
12. Sanity checks
===============================================================================
*/

SELECT
    COUNT(*) FILTER (
        WHERE opinion_date < DATE '1971-01-01'
          AND confidence_tier <> 'rejected_before_1971'
    ) AS n_pre1971_not_rejected,

    COUNT(*) FILTER (
        WHERE confidence_tier = 'tier_a_exact_date'
          AND judgment_date_diff_days <> 0
    ) AS n_invalid_tier_a,

    COUNT(*) FILTER (
        WHERE confidence_tier = 'tier_b_within_7_days'
          AND judgment_date_diff_days NOT BETWEEN 1 AND 7
    ) AS n_invalid_tier_b,

    COUNT(*) FILTER (
        WHERE confidence_tier = 'tier_c_within_30_days'
          AND judgment_date_diff_days NOT BETWEEN 8 AND 30
    ) AS n_invalid_tier_c

FROM tmp_fjc_match_confidence;
