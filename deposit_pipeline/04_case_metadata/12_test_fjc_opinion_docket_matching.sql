/*
===============================================================================
12_test_fjc_opinion_docket_matching.sql
===============================================================================

Purpose
-------
Evaluate whether CourtListener appellate opinions can be linked to the
normalized FJC appellate records through:

    1. CourtListener court_id
    2. a normalized seven-character docket number

CourtListener docket numbers of the form:

    YY-NNNNN
    YY-NNNN
    No. YY-NNNN-cr
    YY-NNNNP

are converted to the FJC format:

    YY + five-digit sequence number

Examples
--------
    15-40079                         -> 1540079
    18-2952                          -> 1802952
    15-2025P                         -> 1502025
    No. 15-3313-cr; August Term ...  -> 1503313

This script does not create the final linkage table. It only measures:

    - parseability of CourtListener docket numbers
    - number of FJC candidates per opinion
    - unique matches
    - ambiguous matches
    - unmatched opinions
    - coverage by court

Input tables
------------
    search_opinion
    search_opinioncluster
    search_docket
    ext.fjc_appellate_normalized

===============================================================================
*/

\pset pager off
\timing on


/*
===============================================================================
1. Build a temporary opinion-level matching base
===============================================================================
*/

DROP TABLE IF EXISTS tmp_fjc_opinion_match_test;

CREATE TEMP TABLE tmp_fjc_opinion_match_test AS
WITH opinion_base AS (
    SELECT
        o.id AS opinion_id,
        o.cluster_id,
        c.docket_id,
        c.date_filed AS opinion_date,
        d.court_id,
        d.docket_number
    FROM search_opinion o
    JOIN search_opinioncluster c
        ON c.id = o.cluster_id
    JOIN search_docket d
        ON d.id = c.docket_id
    WHERE d.court_id IN (
        'ca1', 'ca2', 'ca3', 'ca4', 'ca5', 'ca6',
        'ca7', 'ca8', 'ca9', 'ca10', 'ca11', 'cadc'
    )
),
parsed AS (
    SELECT
        ob.*,
        regexp_match(
            ob.docket_number,
            '^\s*(?:No\.\s*)?([0-9]{2})-([0-9]{1,5})'
        ) AS docket_parts
    FROM opinion_base ob
),
normalized AS (
    SELECT
        p.*,
        CASE
            WHEN p.docket_parts IS NOT NULL
            THEN
                p.docket_parts[1]
                || lpad(p.docket_parts[2], 5, '0')
        END AS fjc_docket_candidate
    FROM parsed p
),
candidate_counts AS (
    SELECT
        n.opinion_id,
        n.cluster_id,
        n.docket_id,
        n.opinion_date,
        n.court_id,
        n.docket_number,
        n.fjc_docket_candidate,
        COUNT(f.fjc_appeal_id) AS n_fjc_candidates,
        MIN(f.fjc_appeal_id) AS unique_fjc_appeal_id
    FROM normalized n
    LEFT JOIN ext.fjc_appellate_normalized f
        ON f.court_id = n.court_id
       AND lpad(f.fjc_docket_raw, 7, '0')
           = n.fjc_docket_candidate
    GROUP BY
        n.opinion_id,
        n.cluster_id,
        n.docket_id,
        n.opinion_date,
        n.court_id,
        n.docket_number,
        n.fjc_docket_candidate
)
SELECT
    opinion_id,
    cluster_id,
    docket_id,
    opinion_date,
    court_id,
    docket_number,
    fjc_docket_candidate,
    n_fjc_candidates,

    CASE
        WHEN fjc_docket_candidate IS NULL THEN 'not_parseable'
        WHEN n_fjc_candidates = 0 THEN 'no_match'
        WHEN n_fjc_candidates = 1 THEN 'unique_match'
        ELSE 'ambiguous_match'
    END AS match_status,

    CASE
        WHEN n_fjc_candidates = 1
        THEN unique_fjc_appeal_id
    END AS fjc_appeal_id

FROM candidate_counts;

ANALYZE tmp_fjc_opinion_match_test;


/*
===============================================================================
2. Overall matching results
===============================================================================
*/

SELECT
    COUNT(*) AS n_opinions,

    COUNT(*) FILTER (
        WHERE fjc_docket_candidate IS NOT NULL
    ) AS n_parseable,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE fjc_docket_candidate IS NOT NULL
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_parseable,

    COUNT(*) FILTER (
        WHERE match_status = 'unique_match'
    ) AS n_unique_matches,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE match_status = 'unique_match'
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_unique_matches,

    COUNT(*) FILTER (
        WHERE match_status = 'ambiguous_match'
    ) AS n_ambiguous_matches,

    COUNT(*) FILTER (
        WHERE match_status = 'no_match'
    ) AS n_no_match,

    COUNT(*) FILTER (
        WHERE match_status = 'not_parseable'
    ) AS n_not_parseable

FROM tmp_fjc_opinion_match_test;


/*
===============================================================================
3. Matching results by court
===============================================================================
*/

SELECT
    court_id,
    COUNT(*) AS n_opinions,

    COUNT(*) FILTER (
        WHERE fjc_docket_candidate IS NOT NULL
    ) AS n_parseable,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE fjc_docket_candidate IS NOT NULL
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_parseable,

    COUNT(*) FILTER (
        WHERE match_status = 'unique_match'
    ) AS n_unique_matches,

    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE match_status = 'unique_match'
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS pct_unique_matches,

    COUNT(*) FILTER (
        WHERE match_status = 'ambiguous_match'
    ) AS n_ambiguous_matches,

    COUNT(*) FILTER (
        WHERE match_status = 'no_match'
    ) AS n_no_match,

    COUNT(*) FILTER (
        WHERE match_status = 'not_parseable'
    ) AS n_not_parseable

FROM tmp_fjc_opinion_match_test
GROUP BY court_id
ORDER BY court_id;


/*
===============================================================================
4. Candidate-count distribution
===============================================================================
*/

SELECT
    n_fjc_candidates,
    COUNT(*) AS n_opinions
FROM tmp_fjc_opinion_match_test
WHERE fjc_docket_candidate IS NOT NULL
GROUP BY n_fjc_candidates
ORDER BY n_fjc_candidates;


/*
===============================================================================
5. Sample unique matches with FJC outcome data
===============================================================================
*/

SELECT
    m.opinion_id,
    m.cluster_id,
    m.docket_id,
    m.opinion_date,
    m.court_id,
    m.docket_number,
    m.fjc_docket_candidate,
    m.fjc_appeal_id,
    f.docket_date_raw AS fjc_docket_date_raw,
    f.judgment_date_raw AS fjc_judgment_date_raw,
    f.disposition_code AS fjc_disposition_code,
    f.outcome_code AS fjc_outcome_code,
    f.appellant,
    f.appellee
FROM tmp_fjc_opinion_match_test m
JOIN ext.fjc_appellate_normalized f
    ON f.fjc_appeal_id = m.fjc_appeal_id
WHERE m.match_status = 'unique_match'
ORDER BY RANDOM()
LIMIT 100;


/*
===============================================================================
6. Sample unmatched but parseable opinions
===============================================================================
*/

SELECT
    opinion_id,
    cluster_id,
    docket_id,
    opinion_date,
    court_id,
    docket_number,
    fjc_docket_candidate
FROM tmp_fjc_opinion_match_test
WHERE match_status = 'no_match'
ORDER BY RANDOM()
LIMIT 100;


/*
===============================================================================
7. Sample unparseable CourtListener docket numbers
===============================================================================
*/

SELECT
    opinion_id,
    cluster_id,
    docket_id,
    opinion_date,
    court_id,
    docket_number
FROM tmp_fjc_opinion_match_test
WHERE match_status = 'not_parseable'
ORDER BY RANDOM()
LIMIT 100;


/*
===============================================================================
8. Sample ambiguous matches
===============================================================================
*/

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
    f.docket_date_raw,
    f.judgment_date_raw,
    f.outcome_code,
    f.appellant,
    f.appellee
FROM tmp_fjc_opinion_match_test m
JOIN ext.fjc_appellate_normalized f
    ON f.court_id = m.court_id
   AND lpad(f.fjc_docket_raw, 7, '0')
       = m.fjc_docket_candidate
WHERE m.match_status = 'ambiguous_match'
ORDER BY m.opinion_id, f.fjc_appeal_id
LIMIT 200;


/*
===============================================================================
9. Date agreement among unique matches
===============================================================================
*/

WITH matched_dates AS (
    SELECT
        m.opinion_id,
        m.court_id,
        m.opinion_date,
        f.source_period,

        CASE
            WHEN f.judgment_date_raw
                 ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN TO_DATE(f.judgment_date_raw, 'MM/DD/YYYY')
        END AS fjc_judgment_date,

        CASE
            WHEN f.docket_date_raw
                 ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN TO_DATE(f.docket_date_raw, 'MM/DD/YYYY')
        END AS fjc_docket_date

    FROM tmp_fjc_opinion_match_test m
    JOIN ext.fjc_appellate_normalized f
        ON f.fjc_appeal_id = m.fjc_appeal_id
    WHERE m.match_status = 'unique_match'
)
SELECT
    COUNT(*) AS n_unique_matches,

    COUNT(fjc_judgment_date) AS n_with_fjc_judgment_date,

    COUNT(*) FILTER (
        WHERE opinion_date = fjc_judgment_date
    ) AS n_exact_judgment_date,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE opinion_date = fjc_judgment_date
        ) / NULLIF(COUNT(fjc_judgment_date), 0),
        2
    ) AS pct_exact_judgment_date,

    COUNT(*) FILTER (
        WHERE ABS(opinion_date - fjc_judgment_date) <= 1
    ) AS n_judgment_within_1_day,

    COUNT(*) FILTER (
        WHERE ABS(opinion_date - fjc_judgment_date) <= 7
    ) AS n_judgment_within_7_days,

    COUNT(*) FILTER (
        WHERE ABS(opinion_date - fjc_judgment_date) <= 30
    ) AS n_judgment_within_30_days,

    COUNT(*) FILTER (
        WHERE fjc_docket_date <= opinion_date
    ) AS n_docket_date_before_opinion

FROM matched_dates;

/*
===============================================================================
11. Matching coverage by opinion period
===============================================================================
*/

WITH periodized AS (
    SELECT
        *,
        CASE
            WHEN opinion_date < DATE '1971-01-01'
                THEN 'before_1971_not_covered_by_fjc'
            WHEN opinion_date < DATE '2008-01-01'
                THEN '1971to2007'
            ELSE '2008plus'
        END AS opinion_period,

        CASE
            WHEN opinion_date < DATE '1971-01-01' THEN 1
            WHEN opinion_date < DATE '2008-01-01' THEN 2
            ELSE 3
        END AS period_order

    FROM tmp_fjc_opinion_match_test
)
SELECT
    opinion_period,
    COUNT(*) AS n_opinions,

    COUNT(*) FILTER (
        WHERE match_status = 'unique_match'
    ) AS n_unique_matches,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE match_status = 'unique_match'
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_unique_matches,

    COUNT(*) FILTER (
        WHERE match_status = 'ambiguous_match'
    ) AS n_ambiguous_matches,

    COUNT(*) FILTER (
        WHERE match_status = 'no_match'
    ) AS n_no_match,

    COUNT(*) FILTER (
        WHERE match_status = 'not_parseable'
    ) AS n_not_parseable

FROM periodized
GROUP BY opinion_period, period_order
ORDER BY period_order;