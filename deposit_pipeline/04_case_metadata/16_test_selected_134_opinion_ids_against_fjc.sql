/*
Complete corrected script.
Run the ENTIRE file in one psql session because it uses temporary tables.
Target variable: FJC outcome_code.
*/

\pset pager off
\timing on

DROP TABLE IF EXISTS tmp_requested_opinion_fjc_candidates;

CREATE TEMP TABLE tmp_requested_opinion_fjc_candidates AS
WITH requested(opinion_id) AS (
    VALUES
        (8410629),
        (11214099),
        (11128187),
        (4445558),
        (9940038),
        (3211607),
        (4117395),
        (9885873),
        (4412169),
        (3204844),
        (9820609),
        (9378746),
        (11205989),
        (3194709),
        (4209652),
        (8413901),
        (8484433),
        (9371749),
        (2780460),
        (10819774),
        (4670749),
        (9915536),
        (4242271),
        (4208621),
        (9322914),
        (9974406),
        (4179435),
        (5515839),
        (11112826),
        (4643301),
        (9379817),
        (4397608),
        (4243039),
        (6118805),
        (8212403),
        (9399386),
        (4702876),
        (11140963),
        (5125336),
        (4241430),
        (4539484),
        (7800988),
        (4546604),
        (4307343),
        (4183530),
        (4148211),
        (3195979),
        (4529044),
        (5130557),
        (5140477),
        (4233128),
        (2807980),
        (4024293),
        (3206083),
        (4666743),
        (4421516),
        (4215923),
        (4317417),
        (4635395),
        (4708950),
        (4151777),
        (9407323),
        (4192093),
        (2828439),
        (4553377),
        (4564883),
        (10776259),
        (8415251),
        (4117471),
        (4256283),
        (4148222),
        (4225121),
        (4663785),
        (3216457),
        (9964506),
        (4547186),
        (9410975),
        (9912482),
        (3162462),
        (4471447),
        (4398716),
        (4294044),
        (10821932),
        (4508327),
        (9834671),
        (9966225),
        (4675717),
        (11065812),
        (8410833),
        (4017830),
        (9390765),
        (9963025),
        (9837619),
        (9290213),
        (4505175),
        (4228954),
        (9693809),
        (3180766),
        (10747826),
        (4281776),
        (4383055),
        (9878639),
        (8413273),
        (9879727),
        (9399975),
        (8414320),
        (4704876),
        (4413471),
        (3153969),
        (4695245),
        (4176707),
        (4540111),
        (2811437),
        (11122385),
        (11176419),
        (2833031),
        (9960547),
        (4398222),
        (4193356),
        (4555480),
        (4362446),
        (11106974),
        (11131220),
        (6317597),
        (4702054),
        (4239944),
        (9867764),
        (4272320),
        (3183425),
        (4995033),
        (11166259),
        (4537247),
        (3152006),
        (10750398)
),
opinion_base AS (
    SELECT
        r.opinion_id AS requested_opinion_id,
        o.id AS opinion_id,
        o.cluster_id,
        c.docket_id,
        c.date_filed AS opinion_date,
        d.court_id,
        d.docket_number
    FROM requested r
    LEFT JOIN search_opinion o ON o.id = r.opinion_id
    LEFT JOIN search_opinioncluster c ON c.id = o.cluster_id
    LEFT JOIN search_docket d ON d.id = c.docket_id
),
parsed AS (
    SELECT
        ob.*,
        regexp_match(ob.docket_number, '([0-9]{2})-([0-9]{1,5})') AS docket_parts
    FROM opinion_base ob
),
normalized AS (
    SELECT
        p.*,
        CASE
            WHEN p.docket_parts IS NOT NULL
            THEN p.docket_parts[1] || lpad(p.docket_parts[2], 5, '0')
        END AS fjc_docket_candidate
    FROM parsed p
),
candidate_rows AS (
    SELECT
        n.requested_opinion_id,
        n.opinion_id,
        n.cluster_id,
        n.docket_id,
        n.opinion_date,
        n.court_id,
        n.docket_number,
        n.fjc_docket_candidate,
        f.fjc_appeal_id,
        f.fjc_docket_raw,
        f.source_period,
        f.docket_date_raw,
        f.judgment_date_raw,
        f.disposition_code,
        f.outcome_code,
        f.appellant,
        f.appellee,
        CASE
            WHEN f.judgment_date_raw ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN to_date(f.judgment_date_raw, 'MM/DD/YYYY')
        END AS fjc_judgment_date
    FROM normalized n
    LEFT JOIN ext.fjc_appellate_normalized f
      ON f.court_id = n.court_id
     AND lpad(f.fjc_docket_raw, 7, '0') = n.fjc_docket_candidate
),
scored AS (
    SELECT
        cr.*,
        count(cr.fjc_appeal_id) OVER (
            PARTITION BY cr.requested_opinion_id
        ) AS n_fjc_candidates,
        CASE
            WHEN cr.opinion_date IS NOT NULL
             AND cr.fjc_judgment_date IS NOT NULL
            THEN abs(cr.opinion_date - cr.fjc_judgment_date)
        END AS judgment_date_diff_days
    FROM candidate_rows cr
),
ranked AS (
    SELECT
        s.*,
        row_number() OVER (
            PARTITION BY s.requested_opinion_id
            ORDER BY s.judgment_date_diff_days NULLS LAST,
                     s.fjc_appeal_id NULLS LAST
        ) AS candidate_rank,
        count(*) FILTER (
            WHERE s.judgment_date_diff_days = x.min_diff
        ) OVER (
            PARTITION BY s.requested_opinion_id
        ) AS n_candidates_at_best_date_distance
    FROM scored s
    LEFT JOIN LATERAL (
        SELECT min(s2.judgment_date_diff_days) AS min_diff
        FROM scored s2
        WHERE s2.requested_opinion_id = s.requested_opinion_id
    ) x ON TRUE
)
SELECT *
FROM ranked;

ANALYZE tmp_requested_opinion_fjc_candidates;

-- Match overview
SELECT
    requested_opinion_id AS opinion_id,
    cluster_id,
    docket_id,
    opinion_date,
    court_id,
    docket_number,
    fjc_docket_candidate,
    n_fjc_candidates,
    CASE
        WHEN opinion_id IS NULL THEN 'opinion_not_found'
        WHEN court_id NOT IN (
            'ca1','ca2','ca3','ca4','ca5','ca6',
            'ca7','ca8','ca9','ca10','ca11','cadc'
        ) THEN 'not_supported_appellate_court'
        WHEN fjc_docket_candidate IS NULL THEN 'not_parseable'
        WHEN n_fjc_candidates = 0 THEN 'no_fjc_match'
        WHEN n_fjc_candidates = 1 THEN 'unique_docket_match'
        WHEN n_candidates_at_best_date_distance = 1
            THEN 'ambiguous_docket_but_unique_best_date'
        ELSE 'ambiguous_unresolved'
    END AS match_result,
    fjc_appeal_id AS best_fjc_appeal_id,
    fjc_judgment_date AS best_fjc_judgment_date,
    judgment_date_diff_days,
    appellant,
    appellee,
    disposition_code,
    outcome_code
FROM tmp_requested_opinion_fjc_candidates
WHERE candidate_rank = 1
ORDER BY requested_opinion_id;

-- Match summary
WITH overview AS (
    SELECT *,
        CASE
            WHEN opinion_id IS NULL THEN 'opinion_not_found'
            WHEN fjc_docket_candidate IS NULL THEN 'not_parseable'
            WHEN n_fjc_candidates = 0 THEN 'no_fjc_match'
            WHEN n_fjc_candidates = 1 THEN 'unique_docket_match'
            WHEN n_candidates_at_best_date_distance = 1
                THEN 'ambiguous_docket_but_unique_best_date'
            ELSE 'ambiguous_unresolved'
        END AS match_result
    FROM tmp_requested_opinion_fjc_candidates
    WHERE candidate_rank = 1
)
SELECT
    count(*) AS n_requested,
    count(*) FILTER (WHERE match_result = 'unique_docket_match') AS n_unique_docket_match,
    count(*) FILTER (WHERE match_result = 'ambiguous_docket_but_unique_best_date') AS n_ambiguous_resolved_by_date,
    count(*) FILTER (WHERE match_result = 'ambiguous_unresolved') AS n_ambiguous_unresolved,
    count(*) FILTER (WHERE match_result = 'no_fjc_match') AS n_no_fjc_match,
    count(*) FILTER (WHERE match_result = 'not_parseable') AS n_not_parseable,
    count(*) FILTER (WHERE judgment_date_diff_days = 0) AS n_exact_judgment_date,
    count(*) FILTER (WHERE judgment_date_diff_days <= 7) AS n_judgment_within_7_days,
    count(*) FILTER (WHERE judgment_date_diff_days <= 30) AS n_judgment_within_30_days,
    count(*) FILTER (WHERE judgment_date_diff_days > 30) AS n_judgment_over_30_days
FROM overview;

-- Integrity
SELECT
    count(*) AS n_overview_rows,
    count(DISTINCT requested_opinion_id) AS n_distinct_requested_ids,
    count(*) - count(DISTINCT requested_opinion_id) AS duplicate_overview_rows
FROM tmp_requested_opinion_fjc_candidates
WHERE candidate_rank = 1;

DROP TABLE IF EXISTS tmp_selected_opinion_outcome_check;

CREATE TEMP TABLE tmp_selected_opinion_outcome_check AS
WITH best_match AS (
    SELECT *
    FROM tmp_requested_opinion_fjc_candidates
    WHERE candidate_rank = 1
),
with_text AS (
    SELECT
        bm.*,
        CASE bm.disposition_code::text
            WHEN '1' THEN 'merits_after_oral_hearing'
            WHEN '2' THEN 'merits_without_oral_hearing'
            WHEN '3' THEN 'merits_without_hearing_court_rule'
            WHEN '4' THEN 'procedural_after_judicial_action'
            WHEN '5' THEN 'procedural_without_judicial_action'
            WHEN '-8' THEN 'missing_or_invalid'
            ELSE 'unknown_disposition_code'
        END AS disposition_label,
        CASE bm.outcome_code::text
            WHEN '1' THEN 'affirmed_or_enforced'
            WHEN '2' THEN 'reversed_or_vacated'
            WHEN '3' THEN 'affirmed_in_part_reversed_in_part'
            WHEN '5' THEN 'dismissed_frivolous'
            WHEN '6' THEN 'remanded'
            WHEN '7' THEN 'other'
            WHEN '-8' THEN 'missing_or_invalid'
            ELSE 'unknown_or_not_applicable'
        END AS fjc_outcome_label,
        coalesce(
            nullif(o.plain_text, ''),
            nullif(regexp_replace(o.html_with_citations, '<[^>]+>', ' ', 'g'), ''),
            nullif(regexp_replace(o.html, '<[^>]+>', ' ', 'g'), ''),
            nullif(regexp_replace(o.html_lawbox, '<[^>]+>', ' ', 'g'), ''),
            nullif(regexp_replace(o.html_columbia, '<[^>]+>', ' ', 'g'), ''),
            nullif(regexp_replace(o.html_anon_2020, '<[^>]+>', ' ', 'g'), '')
        ) AS opinion_text_raw
    FROM best_match bm
    LEFT JOIN search_opinion o
      ON o.id = bm.requested_opinion_id
),
cleaned AS (
    SELECT
        wt.*,
        regexp_replace(
            regexp_replace(coalesce(wt.opinion_text_raw, ''), E'[\n\r\t\f]+', ' ', 'g'),
            E' {2,}', ' ', 'g'
        ) AS opinion_text_clean
    FROM with_text wt
),
with_ending AS (
    SELECT
        c.*,
        right(c.opinion_text_clean, 8000) AS outcome_text_ending
    FROM cleaned c
),
flags AS (
    SELECT
        we.*,
        (we.outcome_text_ending ~* '\m(affirm|affirmed|affirming|enforce|enforced|enforcing)\M'
         OR we.outcome_text_ending ~* '(petition|application|motion)[^.;]{0,120}\m(denied|deny)\M'
         OR we.outcome_text_ending ~* '\m(denied|deny)\M[^.;]{0,120}(petition|application|motion)')
            AS ending_mentions_affirmed_or_enforced,
        (we.outcome_text_ending ~* '\m(reverse|reversed|reversing|vacate|vacated|vacating)\M')
            AS ending_mentions_reversed_or_vacated,
        (we.outcome_text_ending ~* '\m(remand|remanded|remanding)\M')
            AS ending_mentions_remanded,
        (we.outcome_text_ending ~* '\m(dismiss|dismissed|dismissing)\M')
            AS ending_mentions_dismissed,
        (we.outcome_text_ending ~* '\mfrivolous\M')
            AS ending_mentions_frivolous,
        (
          we.outcome_text_ending ~* '(judgment|order|decision|conviction|sentence)[^.;]{0,150}\m(is|are|be)\M[^.;]{0,50}\m(affirmed|enforced)\M'
          OR we.outcome_text_ending ~* '\mwe\M[^.;]{0,80}\m(affirm|enforce)\M'
        ) AS strong_affirmance_phrase,
        (
          we.outcome_text_ending ~* '(judgment|order|decision|conviction|sentence)[^.;]{0,150}\m(is|are|be)\M[^.;]{0,50}\m(reversed|vacated)\M'
          OR we.outcome_text_ending ~* '\mwe\M[^.;]{0,80}\m(reverse|vacate)\M'
        ) AS strong_reversal_phrase,
        (
          we.outcome_text_ending ~* '\mwe\M[^.;]{0,120}\mremand\M'
          OR we.outcome_text_ending ~* '\mremanded\M[^.;]{0,120}(district court|agency|board|bia|lower court)'
          OR we.outcome_text_ending ~* '(district court|agency|board|bia|lower court)[^.;]{0,120}\mremanded\M'
        ) AS strong_remand_phrase,
        (
          we.outcome_text_ending ~* '\mwe\M[^.;]{0,100}\mdismiss\M'
          OR we.outcome_text_ending ~* '(appeal|petition|application|case)[^.;]{0,120}\m(is|are)\M[^.;]{0,50}\mdismissed\M'
        ) AS strong_dismissal_phrase
    FROM with_ending we
)
SELECT
    f.*,
    CASE
        WHEN nullif(f.opinion_text_clean, '') IS NULL THEN NULL
        WHEN f.ending_mentions_affirmed_or_enforced
         AND f.ending_mentions_reversed_or_vacated
            THEN 'affirmed_in_part_reversed_in_part'
        WHEN f.strong_reversal_phrase THEN 'reversed_or_vacated'
        WHEN f.strong_affirmance_phrase THEN 'affirmed_or_enforced'
        WHEN f.strong_remand_phrase
         AND NOT f.strong_reversal_phrase
         AND NOT f.strong_affirmance_phrase THEN 'remanded'
        WHEN f.strong_dismissal_phrase THEN 'dismissed'
        WHEN f.ending_mentions_reversed_or_vacated THEN 'possible_reversed_or_vacated'
        WHEN f.ending_mentions_affirmed_or_enforced THEN 'possible_affirmed_or_enforced'
        WHEN f.ending_mentions_remanded THEN 'possible_remanded'
        WHEN f.ending_mentions_dismissed THEN 'possible_dismissed'
        ELSE 'outcome_not_detected'
    END AS detected_text_outcome
FROM flags f;

ANALYZE tmp_selected_opinion_outcome_check;

DROP TABLE IF EXISTS tmp_selected_opinion_outcome_validation;

CREATE TEMP TABLE tmp_selected_opinion_outcome_validation AS
SELECT
    t.*,
    CASE
        WHEN nullif(t.opinion_text_clean, '') IS NULL
            THEN 'review_no_opinion_text'
        WHEN t.fjc_outcome_label = 'affirmed_or_enforced'
         AND (
                t.strong_affirmance_phrase
             OR (t.ending_mentions_affirmed_or_enforced AND NOT t.strong_reversal_phrase)
         )
            THEN 'text_supports_fjc'
        WHEN t.fjc_outcome_label = 'reversed_or_vacated'
         AND (
                t.strong_reversal_phrase
             OR (t.ending_mentions_reversed_or_vacated AND NOT t.strong_affirmance_phrase)
         )
            THEN 'text_supports_fjc'
        WHEN t.fjc_outcome_label = 'affirmed_in_part_reversed_in_part'
         AND t.ending_mentions_affirmed_or_enforced
         AND t.ending_mentions_reversed_or_vacated
            THEN 'text_supports_fjc'
        WHEN t.fjc_outcome_label = 'dismissed_frivolous'
         AND t.ending_mentions_dismissed
         AND t.ending_mentions_frivolous
            THEN 'text_supports_fjc'
        WHEN t.fjc_outcome_label = 'dismissed_frivolous'
         AND t.ending_mentions_dismissed
            THEN 'review_dismissed_but_frivolous_not_found'
        WHEN t.fjc_outcome_label = 'remanded'
         AND (t.strong_remand_phrase OR t.ending_mentions_remanded)
            THEN 'text_supports_fjc'
        WHEN t.fjc_outcome_label IN (
            'other','missing_or_invalid','unknown_or_not_applicable'
        )
            THEN 'manual_review_nonstandard_outcome'
        WHEN t.fjc_outcome_label = 'affirmed_or_enforced'
         AND t.strong_reversal_phrase
         AND NOT t.strong_affirmance_phrase
            THEN 'possible_fjc_text_conflict'
        WHEN t.fjc_outcome_label = 'reversed_or_vacated'
         AND t.strong_affirmance_phrase
         AND NOT t.strong_reversal_phrase
            THEN 'possible_fjc_text_conflict'
        WHEN t.fjc_outcome_label = 'remanded'
         AND (t.strong_affirmance_phrase OR t.strong_reversal_phrase)
         AND NOT t.ending_mentions_remanded
            THEN 'possible_fjc_text_conflict'
        ELSE 'review_outcome_phrase_not_found'
    END AS text_validation_status
FROM tmp_selected_opinion_outcome_check t;

ANALYZE tmp_selected_opinion_outcome_validation;

-- Detailed validation output
SELECT
    requested_opinion_id AS opinion_id,
    court_id,
    docket_number,
    opinion_date,
    fjc_appeal_id,
    fjc_judgment_date,
    judgment_date_diff_days,
    disposition_code,
    disposition_label,
    outcome_code,
    fjc_outcome_label,
    detected_text_outcome,
    text_validation_status,
    outcome_text_ending AS likely_outcome_text
FROM tmp_selected_opinion_outcome_validation
ORDER BY
    CASE text_validation_status
        WHEN 'possible_fjc_text_conflict' THEN 1
        WHEN 'review_outcome_phrase_not_found' THEN 2
        WHEN 'review_dismissed_but_frivolous_not_found' THEN 3
        WHEN 'manual_review_nonstandard_outcome' THEN 4
        WHEN 'review_no_opinion_text' THEN 5
        WHEN 'text_supports_fjc' THEN 6
        ELSE 7
    END,
    requested_opinion_id;

-- Summary
SELECT
    fjc_outcome_label,
    text_validation_status,
    count(*) AS n_opinions,
    count(*) FILTER (WHERE judgment_date_diff_days = 0) AS n_exact_date,
    count(*) FILTER (WHERE judgment_date_diff_days BETWEEN 1 AND 7) AS n_within_7_days,
    count(*) FILTER (WHERE judgment_date_diff_days BETWEEN 8 AND 30) AS n_within_30_days,
    count(*) FILTER (WHERE judgment_date_diff_days > 30) AS n_over_30_days
FROM tmp_selected_opinion_outcome_validation
GROUP BY fjc_outcome_label, text_validation_status
ORDER BY fjc_outcome_label, text_validation_status;

-- Only review cases
SELECT
    requested_opinion_id AS opinion_id,
    court_id,
    docket_number,
    opinion_date,
    fjc_appeal_id,
    fjc_judgment_date,
    judgment_date_diff_days,
    outcome_code,
    fjc_outcome_label,
    detected_text_outcome,
    text_validation_status,
    outcome_text_ending AS likely_outcome_text
FROM tmp_selected_opinion_outcome_validation
WHERE text_validation_status <> 'text_supports_fjc'
ORDER BY
    CASE text_validation_status
        WHEN 'possible_fjc_text_conflict' THEN 1
        WHEN 'review_outcome_phrase_not_found' THEN 2
        WHEN 'review_dismissed_but_frivolous_not_found' THEN 3
        WHEN 'manual_review_nonstandard_outcome' THEN 4
        WHEN 'review_no_opinion_text' THEN 5
        ELSE 6
    END,
    judgment_date_diff_days DESC NULLS LAST,
    requested_opinion_id;
