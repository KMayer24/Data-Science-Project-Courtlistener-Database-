-- ============================================================
-- 03_validation_sample.sql
--
-- Purpose:
--   Draw a manual validation sample of author attributions so that
--   precision can be reported per attribution step.
--
-- Design:
--   Stratified by attribution step, 200 opinions in total, allocated
--   20 / 60 / 60 / 60 across steps 1 to 4.
--
--   Step 1 gets a small control sample, not an equal share. It uses
--   CourtListener's own structured author_id link and performs no name
--   matching at all, so annotating it measures the quality of upstream
--   data rather than the precision of this pipeline. Twenty rows are
--   enough to notice if that link or the annotation procedure itself is
--   unsound; spending a quarter of the budget there would not buy
--   anything about the method.
--
--   Steps 2 to 4 carry the name matching and therefore the risk, step 4
--   most of all: it reads attribution formulas out of HTML and its
--   lower tiers accept surname-only matches.
--
--   The allocation is not proportional to stratum size, because the aim
--   is a precision estimate per step rather than a corpus average. The
--   stratum sizes travel with the file so a corpus-weighted precision
--   can still be computed (validation/score_validation_sample.py).
--
--   Only attributions that resolve to exactly ONE judge are sampled,
--   because those are the ones a human can check against the text.
--
--   The draw is deterministic. Ordering is by md5(opinion_id || salt),
--   NOT by setseed() + random(): with parallel workers the latter does
--   not reproduce the same sample between runs (verified -- two runs
--   with the same seed produced two different sets of 200 opinions).
--   The hash ordering depends only on the row key, so it is stable
--   across plans, parallelism and PostgreSQL versions.
--
-- Output:
--   ext.author_attribution_validation_sample
--
-- The repository audit files are generated from the restored publication
-- database by validation/build_validation_sample.ipynb. That notebook uses
-- the same keyed-hash ordering and records the completed manual annotations.
--
-- Prerequisite: 01_unique_person_attribution.sql
-- ============================================================

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.author_attribution_validation_sample;

CREATE TABLE ext.author_attribution_validation_sample AS
WITH eligible AS (
    SELECT
        r.opinion_id,
        r.cluster_id,
        r.court_id,
        r.court_short_name,
        r.year_filed,
        r.attribution_step,
        r.tier,
        r.tier_label,
        r.gender,
        r.judge_id,
        r.id_registry,
        r.cl_person_id,
        r.fjc_nid,
        r.judge_display_name,

        -- The string the match was actually based on, per step
        CASE r.attribution_step
            WHEN 1 THEN h.author_str
            WHEN 2 THEN h.author_str
            WHEN 3 THEN h.xml_extracted_author_name
            WHEN 4 THEN h.html_extracted_author_name
        END AS extracted_name,

        -- How the string was obtained (diagnostic context)
        CASE r.attribution_step
            WHEN 1 THEN 'structured author_id = ' || COALESCE(h.author_id::text, '')
            WHEN 2 THEN 'author_str normalised to: ' || COALESCE(h.previous_final_author_last_name_norm, '')
            WHEN 3 THEN 'xml tag: ' || COALESCE(LEFT(BTRIM(REGEXP_REPLACE(h.xml_raw_author_tag, '\s+', ' ', 'g')), 200), '')
            WHEN 4 THEN 'html pattern: ' || COALESCE(h.html_extraction_pattern, '')
        END AS extraction_context,

        row_number() OVER (
            PARTITION BY r.attribution_step
            ORDER BY md5(r.opinion_id::text || 'epjds-validation-2026')
        ) AS rn
    FROM ext.author_person_resolved r
    JOIN ext.author_gender_final_with_html h USING (opinion_id)
    WHERE r.person_unique
),
drawn AS (
    SELECT * FROM eligible
    WHERE rn <= CASE attribution_step
                    WHEN 1 THEN 20   -- control only, see the header
                    ELSE 60
                END
),
stratum_sizes AS (
    SELECT attribution_step, count(*) AS stratum_size
    FROM ext.author_person_resolved
    WHERE person_unique
    GROUP BY 1
)
SELECT
    d.opinion_id,
    d.cluster_id,
    d.court_id,
    d.court_short_name,
    d.year_filed,
    d.attribution_step,
    s.stratum_size,
    d.tier,
    d.tier_label,
    d.extracted_name,
    d.extraction_context,
    d.judge_display_name    AS matched_judge,
    d.judge_id,
    d.id_registry,
    d.cl_person_id,
    d.fjc_nid,
    d.gender                AS matched_gender,

    -- Text excerpt for the annotator: the opening of the opinion,
    -- where the attribution formula appears. HTML is preferred
    -- because that is what steps 3 and 4 read; tags are stripped.
    LEFT(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                COALESCE(
                    NULLIF(BTRIM(REGEXP_REPLACE(
                        COALESCE(o.html_with_citations, ''),
                        '<[^>]+>', ' ', 'g')), ''),
                    o.plain_text,
                    ''),
                '&[a-zA-Z]+;|&#[0-9]+;', ' ', 'g'),
            '\s+', ' ', 'g'),
        1200) AS text_excerpt,

    'https://www.courtlistener.com/opinion/' || d.cluster_id || '/x/'
        AS courtlistener_link,   -- best-effort convenience link; CourtListener
                                 -- resolves the cluster id and corrects the slug

    -- Annotation columns, to be filled in manually.
    -- verdict: correct | incorrect | unclear
    NULL::text AS verdict,
    NULL::text AS correct_judge_if_incorrect,
    NULL::text AS annotator_note

FROM drawn d
JOIN stratum_sizes s ON s.attribution_step = d.attribution_step
JOIN ext.federal_appeal_opinions o ON o.opinion_id = d.opinion_id
ORDER BY d.attribution_step, d.opinion_id;

ALTER TABLE ext.author_attribution_validation_sample ADD PRIMARY KEY (opinion_id);

COMMENT ON TABLE ext.author_attribution_validation_sample IS
'Stratified manual validation sample (20/60/60/60 opinions across attribution steps 1-4, keyed-hash salt epjds-validation-2026) used to report precision per step.';

COMMIT;
