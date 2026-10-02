/*
Complete corrected script.
Run the ENTIRE file in one psql session because it uses temporary tables.

Target variable: FJC outcome_code.

Official FY 2008-forward OUTCOME definitions:
  1  = Affirmed / Enforced, including affirmed and remanded
  2  = Reversed / Vacated, including reversed/vacated and remanded
  3  = Affirmed in part and reversed/vacated in part, including remand
  5  = Dismissed on the merits, including moot, lack of merit, frivolous
  6  = Remanded only: sole action was to return the entire case
  7  = Other merits outcome
  9  = Certificate of appealability denied
 -8  = Missing

OUTCOME is valid only for merits terminations (DISP 1, 2, or 3) and
not for original proceedings.
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
    LEFT JOIN search_opinion o
        ON o.id = r.opinion_id
    LEFT JOIN search_opinioncluster c
        ON c.id = o.cluster_id
    LEFT JOIN search_docket d
        ON d.id = c.docket_id
),
parsed AS (
    SELECT
        ob.*,
        regexp_match(
            ob.docket_number,
            '([0-9]{2})-([0-9]{1,5})'
        ) AS docket_parts
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
            ORDER BY
                s.judgment_date_diff_days NULLS LAST,
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


/*
===============================================================================
1. Match overview
===============================================================================
*/

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
        WHEN opinion_id IS NULL
            THEN 'opinion_not_found'

        WHEN court_id NOT IN (
            'ca1','ca2','ca3','ca4','ca5','ca6',
            'ca7','ca8','ca9','ca10','ca11','cadc'
        )
            THEN 'not_supported_appellate_court'

        WHEN fjc_docket_candidate IS NULL
            THEN 'not_parseable'

        WHEN n_fjc_candidates = 0
            THEN 'no_fjc_match'

        WHEN n_fjc_candidates = 1
            THEN 'unique_docket_match'

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


/*
===============================================================================
2. Match summary
===============================================================================
*/

WITH overview AS (
    SELECT
        *,

        CASE
            WHEN opinion_id IS NULL
                THEN 'opinion_not_found'

            WHEN court_id NOT IN (
                'ca1','ca2','ca3','ca4','ca5','ca6',
                'ca7','ca8','ca9','ca10','ca11','cadc'
            )
                THEN 'not_supported_appellate_court'

            WHEN fjc_docket_candidate IS NULL
                THEN 'not_parseable'

            WHEN n_fjc_candidates = 0
                THEN 'no_fjc_match'

            WHEN n_fjc_candidates = 1
                THEN 'unique_docket_match'

            WHEN n_candidates_at_best_date_distance = 1
                THEN 'ambiguous_docket_but_unique_best_date'

            ELSE 'ambiguous_unresolved'
        END AS match_result

    FROM tmp_requested_opinion_fjc_candidates
    WHERE candidate_rank = 1
)
SELECT
    count(*) AS n_requested,

    count(*) FILTER (
        WHERE match_result = 'unique_docket_match'
    ) AS n_unique_docket_match,

    count(*) FILTER (
        WHERE match_result = 'ambiguous_docket_but_unique_best_date'
    ) AS n_ambiguous_resolved_by_date,

    count(*) FILTER (
        WHERE match_result = 'ambiguous_unresolved'
    ) AS n_ambiguous_unresolved,

    count(*) FILTER (
        WHERE match_result = 'no_fjc_match'
    ) AS n_no_fjc_match,

    count(*) FILTER (
        WHERE match_result = 'not_parseable'
    ) AS n_not_parseable,

    count(*) FILTER (
        WHERE match_result = 'opinion_not_found'
    ) AS n_opinion_not_found,

    count(*) FILTER (
        WHERE judgment_date_diff_days = 0
    ) AS n_exact_judgment_date,

    count(*) FILTER (
        WHERE judgment_date_diff_days BETWEEN 0 AND 7
    ) AS n_judgment_within_7_days,

    count(*) FILTER (
        WHERE judgment_date_diff_days BETWEEN 0 AND 30
    ) AS n_judgment_within_30_days,

    count(*) FILTER (
        WHERE judgment_date_diff_days > 30
    ) AS n_judgment_over_30_days

FROM overview;


/*
===============================================================================
3. Integrity
===============================================================================
*/

SELECT
    count(*) AS n_overview_rows,
    count(DISTINCT requested_opinion_id) AS n_distinct_requested_ids,
    count(*) - count(DISTINCT requested_opinion_id)
        AS duplicate_overview_rows
FROM tmp_requested_opinion_fjc_candidates
WHERE candidate_rank = 1;


/*
===============================================================================
4. Translate official FJC codes and attach CourtListener opinion text
===============================================================================
*/

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
            WHEN '1'  THEN 'merits_after_oral_hearing'
            WHEN '2'  THEN 'merits_after_submission_without_hearing'
            WHEN '3'  THEN 'merits_without_hearing_court_rule_discontinued'
            WHEN '4'  THEN 'procedural_after_other_judicial_action'
            WHEN '5'  THEN 'procedural_without_judicial_action'
            WHEN '-8' THEN 'missing'
            ELSE 'unknown_disposition_code'
        END AS disposition_label,

        CASE bm.outcome_code::text
            WHEN '1'  THEN 'affirmed_or_enforced'
            WHEN '2'  THEN 'reversed_or_vacated'
            WHEN '3'  THEN 'affirmed_in_part_reversed_or_vacated_in_part'
            WHEN '5'  THEN 'dismissed_on_merits'
            WHEN '6'  THEN 'remanded_only'
            WHEN '7'  THEN 'other_merits_outcome'
            WHEN '9'  THEN 'certificate_of_appealability_denied'
            WHEN '-8' THEN 'missing'
            ELSE 'unknown_or_not_applicable'
        END AS fjc_outcome_label,

        (
            bm.disposition_code::text IN ('1', '2', '3')
        ) AS outcome_code_context_is_merits,

        COALESCE(
            NULLIF(o.plain_text, ''),

            NULLIF(
                regexp_replace(
                    o.html_with_citations,
                    '<[^>]+>',
                    ' ',
                    'g'
                ),
                ''
            ),

            NULLIF(
                regexp_replace(
                    o.html,
                    '<[^>]+>',
                    ' ',
                    'g'
                ),
                ''
            ),

            NULLIF(
                regexp_replace(
                    o.html_lawbox,
                    '<[^>]+>',
                    ' ',
                    'g'
                ),
                ''
            ),

            NULLIF(
                regexp_replace(
                    o.html_columbia,
                    '<[^>]+>',
                    ' ',
                    'g'
                ),
                ''
            ),

            NULLIF(
                regexp_replace(
                    o.html_anon_2020,
                    '<[^>]+>',
                    ' ',
                    'g'
                ),
                ''
            )
        ) AS opinion_text_raw

    FROM best_match bm
    LEFT JOIN search_opinion o
      ON o.id = bm.requested_opinion_id
),
cleaned AS (
    SELECT
        wt.*,

        trim(
            regexp_replace(
                regexp_replace(
                    COALESCE(wt.opinion_text_raw, ''),
                    E'[\n\r\t\f]+',
                    ' ',
                    'g'
                ),
                E' {2,}',
                ' ',
                'g'
            )
        ) AS opinion_text_clean

    FROM with_text wt
),
with_ending AS (
    SELECT
        c.*,

        /*
        Restrict text validation to the final 3,000 characters.
        This usually captures the operative conclusion while excluding
        most citations and procedural history.
        */
        RIGHT(
            c.opinion_text_clean,
            3000
        ) AS outcome_text_ending

    FROM cleaned c
),
operative_flags AS (
    SELECT
        we.*,

        /*
        Explicit mixed result:
        affirmed in part and reversed/vacated in part.
        */
        (
            we.outcome_text_ending ~*
                '\m(affirm|affirmed)\M[^.;]{0,120}\min part\M[^.;]{0,180}\m(reverse|reversed|vacate|vacated)\M[^.;]{0,120}\min part\M'

            OR we.outcome_text_ending ~*
                '\m(reverse|reversed|vacate|vacated)\M[^.;]{0,120}\min part\M[^.;]{0,180}\m(affirm|affirmed)\M[^.;]{0,120}\min part\M'
        ) AS operative_mixed,

        /*
        Affirmance or enforcement.
        Petition denial is treated as affirmance/enforcement for review cases.
        Official FJC Outcome 1 also includes affirmed and remanded.
        */
        (
            we.outcome_text_ending ~*
                '\mwe\M[^.;]{0,50}\m(affirm|enforce)\M'

            OR we.outcome_text_ending ~*
                '\m(judgment|order|decision|conviction|sentence)\M[^.;]{0,100}\m(is|are|be)\M[^.;]{0,30}\m(affirmed|enforced)\M'

            OR we.outcome_text_ending ~*
                '\m(affirmed|enforced)\M\s*[.!]?(\s*[0-9]+)?\s*$'

            OR we.outcome_text_ending ~*
                '\m(petition for review|petition|application)\M[^.;]{0,100}\m(is|are|be)\M[^.;]{0,30}\mdenied\M'

            OR we.outcome_text_ending ~*
                '\mwe\M[^.;]{0,80}\mdeny\M[^.;]{0,80}\m(petition for review|petition|application)\M'
        ) AS operative_affirmed_or_enforced,

        /*
        Reversal or vacatur.
        Petition grant is treated as reversal/vacatur for review cases.
        Official FJC Outcome 2 also includes reversed/vacated and remanded.
        */
        (
            we.outcome_text_ending ~*
                '\mwe\M[^.;]{0,50}\m(reverse|vacate)\M'

            OR we.outcome_text_ending ~*
                '\m(judgment|order|decision|conviction|sentence)\M[^.;]{0,100}\m(is|are|be)\M[^.;]{0,30}\m(reversed|vacated)\M'

            OR we.outcome_text_ending ~*
                '\m(reversed|vacated)\M\s*[.!]?(\s*[0-9]+)?\s*$'

            OR we.outcome_text_ending ~*
                '\m(petition for review|petition|application)\M[^.;]{0,100}\m(is|are|be)\M[^.;]{0,30}\mgranted\M'

            OR we.outcome_text_ending ~*
                '\mwe\M[^.;]{0,80}\mgrant\M[^.;]{0,80}\m(petition for review|petition|application)\M'
        ) AS operative_reversed_or_vacated,

        /*
        Remand. This flag may coexist with affirmance, reversal, or vacatur.
        Outcome 6 is supported only when remand is the sole operative action.
        */
        (
            we.outcome_text_ending ~*
                '\mwe\M[^.;]{0,70}\mremand\M'

            OR we.outcome_text_ending ~*
                '\m(case|matter|proceedings|petition)\M[^.;]{0,100}\m(is|are|be)\M[^.;]{0,30}\mremanded\M'

            OR we.outcome_text_ending ~*
                '\mremanded\M[^.;]{0,100}\m(for|to)\M[^.;]{0,80}\m(further proceedings|district court|agency|board|bia)\M'

            OR we.outcome_text_ending ~*
                '\mremanded\M\s*[.!]?(\s*[0-9]+)?\s*$'
        ) AS operative_remanded,

        /*
        Dismissal on the merits.
        FJC Outcome 5 does not require the word "frivolous".
        */
        (
            we.outcome_text_ending ~*
                '\mwe\M[^.;]{0,70}\mdismiss\M'

            OR we.outcome_text_ending ~*
                '\m(appeal|petition|application|case)\M[^.;]{0,100}\m(is|are|be)\M[^.;]{0,30}\mdismissed\M'

            OR we.outcome_text_ending ~*
                '\mdismissed\M\s*[.!]?(\s*[0-9]+)?\s*$'
        ) AS operative_dismissed,

        /*
        Certificate of appealability denial.
        */
        (
            we.outcome_text_ending ~*
                '\m(certificate of appealability|coa)\M[^.;]{0,120}\m(is|are|be)\M[^.;]{0,30}\mdenied\M'

            OR we.outcome_text_ending ~*
                '\mwe\M[^.;]{0,80}\mdeny\M[^.;]{0,80}\m(certificate of appealability|coa)\M'

            OR we.outcome_text_ending ~*
                '\m(certificate of appealability|coa)\M[^.;]{0,120}\mdenied\M'
        ) AS operative_coa_denied

    FROM with_ending we
)
SELECT
    f.*,

    CASE
        WHEN NULLIF(f.opinion_text_clean, '') IS NULL
            THEN NULL

        WHEN f.operative_mixed
            THEN 'affirmed_in_part_reversed_or_vacated_in_part'

        WHEN f.operative_reversed_or_vacated
         AND f.operative_remanded
            THEN 'reversed_or_vacated_and_remanded'

        WHEN f.operative_affirmed_or_enforced
         AND f.operative_remanded
            THEN 'affirmed_and_remanded'

        WHEN f.operative_reversed_or_vacated
            THEN 'reversed_or_vacated'

        WHEN f.operative_affirmed_or_enforced
            THEN 'affirmed_or_enforced'

        WHEN f.operative_remanded
            THEN 'remanded_only'

        WHEN f.operative_dismissed
            THEN 'dismissed_on_merits'

        WHEN f.operative_coa_denied
            THEN 'certificate_of_appealability_denied'

        ELSE 'outcome_not_detected'
    END AS detected_text_outcome

FROM operative_flags f;

ANALYZE tmp_selected_opinion_outcome_check;


/*
===============================================================================
5. Validate operative opinion language against official FJC OUTCOME definitions
===============================================================================
*/

DROP TABLE IF EXISTS tmp_selected_opinion_outcome_validation;

CREATE TEMP TABLE tmp_selected_opinion_outcome_validation AS
SELECT
    t.*,

    CASE
        WHEN NULLIF(t.opinion_text_clean, '') IS NULL
            THEN 'review_no_opinion_text'

        /*
        OUTCOME should be used only for merits terminations.
        */
        WHEN NOT t.outcome_code_context_is_merits
         AND t.outcome_code::text NOT IN ('-8')
            THEN 'review_outcome_outside_merits_context'

        /*
        FJC Outcome 1 includes:
        - affirmed / enforced
        - affirmed and remanded
        */
        WHEN t.fjc_outcome_label = 'affirmed_or_enforced'
         AND t.operative_affirmed_or_enforced
         AND NOT t.operative_mixed
         AND NOT t.operative_reversed_or_vacated
            THEN 'text_supports_fjc'

        /*
        FJC Outcome 2 includes:
        - reversed / vacated
        - reversed/vacated and remanded
        */
        WHEN t.fjc_outcome_label = 'reversed_or_vacated'
         AND t.operative_reversed_or_vacated
         AND NOT t.operative_mixed
         AND NOT t.operative_affirmed_or_enforced
            THEN 'text_supports_fjc'

        /*
        FJC Outcome 3 includes a mixed merits result,
        whether or not remand is also ordered.
        */
        WHEN t.fjc_outcome_label =
             'affirmed_in_part_reversed_or_vacated_in_part'
         AND (
                t.operative_mixed
             OR (
                    t.operative_affirmed_or_enforced
                AND t.operative_reversed_or_vacated
                )
             )
            THEN 'text_supports_fjc'

        /*
        FJC Outcome 5 is dismissal on the merits.
        It includes moot, lack of merit, and frivolous dismissals.
        */
        WHEN t.fjc_outcome_label = 'dismissed_on_merits'
         AND t.operative_dismissed
            THEN 'text_supports_fjc'

        /*
        FJC Outcome 6 applies only when remand is the sole action.
        */
        WHEN t.fjc_outcome_label = 'remanded_only'
         AND t.operative_remanded
         AND NOT t.operative_mixed
         AND NOT t.operative_affirmed_or_enforced
         AND NOT t.operative_reversed_or_vacated
         AND NOT t.operative_dismissed
            THEN 'text_supports_fjc'

        /*
        FJC Outcome 9: certificate of appealability denied.
        */
        WHEN t.fjc_outcome_label =
             'certificate_of_appealability_denied'
         AND t.operative_coa_denied
            THEN 'text_supports_fjc'

        WHEN t.fjc_outcome_label IN (
            'other_merits_outcome',
            'missing',
            'unknown_or_not_applicable'
        )
            THEN 'manual_review_nonstandard_outcome'

        /*
        Direct conflicts based only on explicit operative language.
        */
        WHEN t.fjc_outcome_label = 'affirmed_or_enforced'
         AND (
                t.operative_reversed_or_vacated
             OR t.operative_mixed
             )
         AND NOT t.operative_affirmed_or_enforced
            THEN 'possible_fjc_text_conflict'

        WHEN t.fjc_outcome_label = 'reversed_or_vacated'
         AND (
                t.operative_affirmed_or_enforced
             OR t.operative_mixed
             )
         AND NOT t.operative_reversed_or_vacated
            THEN 'possible_fjc_text_conflict'

        WHEN t.fjc_outcome_label =
             'affirmed_in_part_reversed_or_vacated_in_part'
         AND (
                t.operative_affirmed_or_enforced
             <> t.operative_reversed_or_vacated
             )
         AND NOT t.operative_mixed
            THEN 'possible_fjc_text_conflict'

        WHEN t.fjc_outcome_label = 'dismissed_on_merits'
         AND (
                t.operative_affirmed_or_enforced
             OR t.operative_reversed_or_vacated
             OR t.operative_remanded
             OR t.operative_mixed
             )
         AND NOT t.operative_dismissed
            THEN 'possible_fjc_text_conflict'

        WHEN t.fjc_outcome_label = 'remanded_only'
         AND (
                t.operative_affirmed_or_enforced
             OR t.operative_reversed_or_vacated
             OR t.operative_mixed
             OR t.operative_dismissed
             )
            THEN 'possible_fjc_text_conflict'

        WHEN t.fjc_outcome_label =
             'certificate_of_appealability_denied'
         AND (
                t.operative_affirmed_or_enforced
             OR t.operative_reversed_or_vacated
             OR t.operative_remanded
             OR t.operative_dismissed
             OR t.operative_mixed
             )
         AND NOT t.operative_coa_denied
            THEN 'possible_fjc_text_conflict'

        ELSE 'review_outcome_phrase_not_found'
    END AS text_validation_status

FROM tmp_selected_opinion_outcome_check t;

ANALYZE tmp_selected_opinion_outcome_validation;


/*
===============================================================================
6. Detailed validation output
===============================================================================
*/

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
    outcome_code_context_is_merits,

    outcome_code,
    fjc_outcome_label,
    detected_text_outcome,
    text_validation_status,

    operative_mixed,
    operative_affirmed_or_enforced,
    operative_reversed_or_vacated,
    operative_remanded,
    operative_dismissed,
    operative_coa_denied,

    outcome_text_ending AS likely_outcome_text

FROM tmp_selected_opinion_outcome_validation
ORDER BY
    CASE text_validation_status
        WHEN 'possible_fjc_text_conflict' THEN 1
        WHEN 'review_outcome_outside_merits_context' THEN 2
        WHEN 'review_outcome_phrase_not_found' THEN 3
        WHEN 'manual_review_nonstandard_outcome' THEN 4
        WHEN 'review_no_opinion_text' THEN 5
        WHEN 'text_supports_fjc' THEN 6
        ELSE 7
    END,
    requested_opinion_id;


/*
===============================================================================
7. Summary
===============================================================================
*/

SELECT
    fjc_outcome_label,
    text_validation_status,
    count(*) AS n_opinions,

    count(*) FILTER (
        WHERE judgment_date_diff_days = 0
    ) AS n_exact_date,

    count(*) FILTER (
        WHERE judgment_date_diff_days BETWEEN 1 AND 7
    ) AS n_within_7_days,

    count(*) FILTER (
        WHERE judgment_date_diff_days BETWEEN 8 AND 30
    ) AS n_within_30_days,

    count(*) FILTER (
        WHERE judgment_date_diff_days > 30
    ) AS n_over_30_days

FROM tmp_selected_opinion_outcome_validation
GROUP BY
    fjc_outcome_label,
    text_validation_status
ORDER BY
    fjc_outcome_label,
    text_validation_status;


/*
===============================================================================
8. Only cases requiring substantive review
===============================================================================
*/

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
    outcome_code_context_is_merits,

    outcome_code,
    fjc_outcome_label,
    detected_text_outcome,
    text_validation_status,

    operative_mixed,
    operative_affirmed_or_enforced,
    operative_reversed_or_vacated,
    operative_remanded,
    operative_dismissed,
    operative_coa_denied,

    outcome_text_ending AS likely_outcome_text

FROM tmp_selected_opinion_outcome_validation
WHERE text_validation_status <> 'text_supports_fjc'
ORDER BY
    CASE text_validation_status
        WHEN 'possible_fjc_text_conflict' THEN 1
        WHEN 'review_outcome_outside_merits_context' THEN 2
        WHEN 'review_outcome_phrase_not_found' THEN 3
        WHEN 'manual_review_nonstandard_outcome' THEN 4
        WHEN 'review_no_opinion_text' THEN 5
        ELSE 6
    END,
    judgment_date_diff_days DESC NULLS LAST,
    requested_opinion_id;


/*
===============================================================================
9. Optional compact review summary by opinion
===============================================================================
*/

SELECT
    requested_opinion_id AS opinion_id,
    court_id,
    docket_number,
    opinion_date,
    fjc_judgment_date,
    judgment_date_diff_days,
    disposition_code,
    outcome_code,
    fjc_outcome_label,
    detected_text_outcome,
    text_validation_status
FROM tmp_selected_opinion_outcome_validation
ORDER BY requested_opinion_id;


/*
Find all CourtListener opinions for the same appellate docket,
especially opinions filed on or near the FJC judgment date.
*/

WITH problem_cases (
    original_opinion_id,
    court_id,
    normalized_fjc_docket,
    fjc_judgment_date
) AS (
    VALUES
        (4017830, 'ca2',  '1501518', DATE '2017-09-11'),
        (4398222, 'ca10', '1801269', DATE '2020-06-16'),
        (9878639, 'ca11', '1513124', DATE '2016-11-03')
),
all_cl_opinions AS (
    SELECT
        pc.original_opinion_id,
        pc.fjc_judgment_date,

        o.id AS candidate_opinion_id,
        o.cluster_id,
        c.date_filed AS candidate_opinion_date,

        d.id AS docket_id,
        d.court_id,
        d.docket_number,

        abs(c.date_filed - pc.fjc_judgment_date)
            AS date_diff_days,

        CASE
            WHEN o.plain_text IS NOT NULL
             AND o.plain_text <> ''
                THEN o.plain_text

            ELSE regexp_replace(
                coalesce(
                    o.html_with_citations,
                    o.html,
                    o.html_lawbox,
                    o.html_columbia,
                    o.html_anon_2020,
                    ''
                ),
                '<[^>]+>',
                ' ',
                'g'
            )
        END AS opinion_text

    FROM problem_cases pc
    JOIN search_docket d
      ON d.court_id = pc.court_id

    JOIN search_opinioncluster c
      ON c.docket_id = d.id

    JOIN search_opinion o
      ON o.cluster_id = c.id

    WHERE
        CASE
            WHEN regexp_match(
                d.docket_number,
                '([0-9]{2})-([0-9]{1,5})'
            ) IS NOT NULL
            THEN
                (
                    regexp_match(
                        d.docket_number,
                        '([0-9]{2})-([0-9]{1,5})'
                    )
                )[1]
                ||
                lpad(
                    (
                        regexp_match(
                            d.docket_number,
                            '([0-9]{2})-([0-9]{1,5})'
                        )
                    )[2],
                    5,
                    '0'
                )
        END = pc.normalized_fjc_docket
)
SELECT
    original_opinion_id,
    candidate_opinion_id,
    cluster_id,
    docket_id,
    court_id,
    docket_number,
    candidate_opinion_date,
    fjc_judgment_date,
    date_diff_days,

    right(
        regexp_replace(
            regexp_replace(
                coalesce(opinion_text, ''),
                E'[\n\r\t\f]+',
                ' ',
                'g'
            ),
            E' {2,}',
            ' ',
            'g'
        ),
        1500
    ) AS opinion_ending

FROM all_cl_opinions
WHERE candidate_opinion_date
      BETWEEN fjc_judgment_date - 30
          AND fjc_judgment_date + 30

ORDER BY
    original_opinion_id,
    date_diff_days,
    candidate_opinion_id;

WITH problem_cases (
    original_opinion_id,
    court_id,
    normalized_fjc_docket,
    fjc_judgment_date
) AS (
    VALUES
        (4017830, 'ca2',  '1501518', DATE '2017-09-11'),
        (4398222, 'ca10', '1801269', DATE '2020-06-16'),
        (9878639, 'ca11', '1513124', DATE '2016-11-03')
),
matches AS (
    SELECT
        pc.original_opinion_id,
        pc.fjc_judgment_date,
        o.id AS candidate_opinion_id,
        c.date_filed AS candidate_opinion_date,
        d.docket_number
    FROM problem_cases pc
    JOIN search_docket d
      ON d.court_id = pc.court_id
    JOIN search_opinioncluster c
      ON c.docket_id = d.id
    JOIN search_opinion o
      ON o.cluster_id = c.id
    WHERE
        CASE
            WHEN regexp_match(
                d.docket_number,
                '([0-9]{2})-([0-9]{1,5})'
            ) IS NOT NULL
            THEN
                (
                    regexp_match(
                        d.docket_number,
                        '([0-9]{2})-([0-9]{1,5})'
                    )
                )[1]
                ||
                lpad(
                    (
                        regexp_match(
                            d.docket_number,
                            '([0-9]{2})-([0-9]{1,5})'
                        )
                    )[2],
                    5,
                    '0'
                )
        END = pc.normalized_fjc_docket
)
SELECT
    original_opinion_id,
    fjc_judgment_date,

    count(*) AS n_all_opinions_for_docket,

    count(*) FILTER (
        WHERE candidate_opinion_date = fjc_judgment_date
    ) AS n_opinions_exactly_on_fjc_date,

    min(abs(candidate_opinion_date - fjc_judgment_date))
        AS nearest_date_difference

FROM matches
GROUP BY
    original_opinion_id,
    fjc_judgment_date
ORDER BY original_opinion_id;