/*
===============================================================================
19_build_fjc_opinion_matches.sql
===============================================================================

Purpose
-------
Materialize a production opinion -> FJC match table, one row per CourtListener
appellate opinion, carrying the single best-matching FJC appeal record plus a
confidence tier. This replaces the exploratory 12-16 test scripts.

Design decisions (locked in from the validation scripts)
--------------------------------------------------------
1. Unit of the FJC side stays fjc_appeal_id. We never dedupe FJC by docket.
   A docket can have several FJC rows (rehearing, multiple proceedings,
   reused numbers). We disambiguate by DATE proximity, not by collapsing.

2. Docket parsing now handles TWO formats. The old parser only anchored on a
   leading "YY-NNNNN" and therefore missed the historical Second-Circuit /
   D.C.-Circuit convention "<running no>, Docket YY-NNNN" and "Docket No.
   YY-NNNN". That single gap caused ca2 (48.8%) and cadc (56.3%) parseability
   vs. ~83% elsewhere -> a circuit-level selection bias. The keyword branch
   below recovers most of it.

3. Among multiple FJC candidates for one opinion we pick the row whose FJC
   judgment date is closest to the opinion date. |diff| drives the tier:
       exact (0d) > near (<=7d) > within_30 (<=30d) > over_30 (review) .
   Over-30-day matches are NOT auto-eligible: those are the wrong-proceeding
   mismatches (e.g. docket 15-1518-cr, 417 days off).

4. outcome_code (result: affirmed/reversed/remanded) and disposition_code
   (procedural mode: after oral argument / on submission) are BOTH carried but
   kept strictly separate. They are different variables. Downstream analysis
   must use outcome_code for "who won", never disposition_code.

Input
-----
    search_opinion, search_opinioncluster, search_docket
    ext.fjc_appellate_normalized   (from 11_create_fjc_appellate_normalized.sql)

Output
------
    ext.fjc_opinion_match          (one row per opinion_id)

===============================================================================
*/

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.fjc_opinion_match;

CREATE TABLE ext.fjc_opinion_match AS
WITH opinion_base AS (
    SELECT
        o.id            AS opinion_id,
        o.cluster_id,
        c.docket_id,
        c.date_filed    AS opinion_date,
        d.court_id,
        d.docket_number
    FROM search_opinion o
    JOIN search_opinioncluster c ON c.id = o.cluster_id
    JOIN search_docket d         ON d.id = c.docket_id
    WHERE d.court_id IN (
        'ca1','ca2','ca3','ca4','ca5','ca6',
        'ca7','ca8','ca9','ca10','ca11','cadc'
    )
),
parsed AS (
    SELECT
        ob.*,
        -- Branch 1: leading docket, modern format  "No. 05-71379", "13-4156-cv"
        regexp_match(ob.docket_number, '^\s*(?:No\.\s*)?([0-9]{2})-([0-9]{1,5})')
            AS lead_parts,
        -- Branch 2: keyword format, ca2 / cadc historical
        --   "1163, Docket 80-1065", "No. 809, Docket 78-1028", "Docket No. 02-7708"
        regexp_match(ob.docket_number, '[Dd]ocket\s*(?:No\.\s*)?([0-9]{2})-([0-9]{1,5})')
            AS kw_parts
    FROM opinion_base ob
),
normalized AS (
    SELECT
        p.*,
        CASE
            WHEN p.lead_parts IS NOT NULL
                THEN p.lead_parts[1] || lpad(p.lead_parts[2], 5, '0')
            WHEN p.kw_parts IS NOT NULL
                THEN p.kw_parts[1]   || lpad(p.kw_parts[2],   5, '0')
        END AS fjc_docket_candidate,
        CASE
            WHEN p.lead_parts IS NOT NULL THEN 'lead'
            WHEN p.kw_parts   IS NOT NULL THEN 'docket_keyword'
            ELSE 'unparseable'
        END AS parse_rule
    FROM parsed p
),
-- one row per (opinion x fjc candidate), with signed date distance
candidates AS (
    SELECT
        n.opinion_id,
        n.cluster_id,
        n.docket_id,
        n.opinion_date,
        n.court_id,
        n.docket_number,
        n.fjc_docket_candidate,
        n.parse_rule,
        f.fjc_appeal_id,
        f.disposition_code,
        f.outcome_code,
        f.nature_of_suit_code,
        f.offense_code,
        f.jurisdiction_code,
        f.appeal_type_code,
        f.agency_code,
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
counted AS (
    SELECT
        c.*,
        CASE
            WHEN fjc_judgment_date IS NOT NULL
            THEN abs(opinion_date - fjc_judgment_date)
        END AS date_diff_days,
        count(fjc_appeal_id) OVER (PARTITION BY opinion_id) AS n_fjc_candidates
    FROM candidates c
),
-- pick the single best FJC row per opinion: closest judgment date, then id
best AS (
    SELECT DISTINCT ON (opinion_id) *
    FROM counted
    ORDER BY opinion_id,
             (date_diff_days IS NULL),   -- rows with a date first
             date_diff_days ASC,
             fjc_appeal_id ASC
)
SELECT
    opinion_id,
    cluster_id,
    docket_id,
    opinion_date,
    court_id,
    docket_number,
    fjc_docket_candidate,
    parse_rule,
    n_fjc_candidates,
    fjc_appeal_id,
    fjc_judgment_date,
    date_diff_days,
    disposition_code,
    outcome_code,
    nature_of_suit_code,
    offense_code,
    jurisdiction_code,
    appeal_type_code,
    agency_code,
    appellant,
    appellee,

    -- confidence tier
    CASE
        WHEN fjc_docket_candidate IS NULL              THEN 'not_parseable'
        WHEN n_fjc_candidates = 0                      THEN 'no_fjc_match'
        WHEN date_diff_days IS NULL                    THEN 'matched_no_date'
        WHEN date_diff_days = 0                         THEN 'exact_date'
        WHEN date_diff_days <= 7                        THEN 'near_date_7'
        WHEN date_diff_days <= 30                       THEN 'within_30'
        ELSE 'over_30_review'
    END AS match_tier,

    (n_fjc_candidates > 1) AS was_ambiguous,

    -- single flag the analysis layer filters on: trustworthy result linkage.
    -- exact or <=7d, and an actual FJC row. Tightenable to date_diff = 0.
    (
        fjc_docket_candidate IS NOT NULL
        AND n_fjc_candidates >= 1
        AND date_diff_days IS NOT NULL
        AND date_diff_days <= 7
    ) AS match_eligible
FROM best;

ALTER TABLE ext.fjc_opinion_match
    ADD CONSTRAINT fjc_opinion_match_pkey PRIMARY KEY (opinion_id);

CREATE INDEX idx_fjc_opinion_match_tier    ON ext.fjc_opinion_match (match_tier);
CREATE INDEX idx_fjc_opinion_match_appeal  ON ext.fjc_opinion_match (fjc_appeal_id);
CREATE INDEX idx_fjc_opinion_match_court   ON ext.fjc_opinion_match (court_id);
CREATE INDEX idx_fjc_opinion_match_elig    ON ext.fjc_opinion_match (match_eligible);

ANALYZE ext.fjc_opinion_match;

COMMIT;


/*
===============================================================================
Validation
===============================================================================
*/

-- 1. Tier distribution overall.
SELECT match_tier, count(*) AS n_opinions,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM ext.fjc_opinion_match
GROUP BY match_tier
ORDER BY n_opinions DESC;

-- 2. Parseability lift by court (watch ca2 / cadc vs. the old 48.8 / 56.3).
SELECT
    court_id,
    count(*) AS n_opinions,
    round(100.0 * count(*) FILTER (WHERE fjc_docket_candidate IS NOT NULL)
          / count(*), 2) AS pct_parseable,
    count(*) FILTER (WHERE parse_rule = 'docket_keyword') AS n_recovered_by_keyword,
    round(100.0 * count(*) FILTER (WHERE match_eligible) / count(*), 2)
          AS pct_match_eligible
FROM ext.fjc_opinion_match
GROUP BY court_id
ORDER BY court_id;

-- 3. Date-agreement sanity among eligible matches.
SELECT
    count(*) AS n_eligible,
    round(100.0 * count(*) FILTER (WHERE date_diff_days = 0) / count(*), 2)
        AS pct_exact,
    round(100.0 * count(*) FILTER (WHERE date_diff_days <= 1) / count(*), 2)
        AS pct_within_1d
FROM ext.fjc_opinion_match
WHERE match_eligible;
