-- ============================================================
-- 11_unique_person_attribution.sql
--
-- Purpose:
--   Determine, for every resolved author attribution, whether the
--   match identifies exactly ONE judge (a unique person), and
--   export the corresponding person identifier.
--
--   This is the distinction between two different things:
--     gender_resolved = TRUE   -> all candidates in the best tier
--                                 agree on GENDER (n_candidate_genders = 1)
--     person unique            -> there is only ONE candidate judge
--                                 (n_candidate_judges = 1)
--
--   The second is strictly stronger. Gender analyses can use the
--   first; any analysis at the level of individual judges (careers,
--   author fixed effects, panel composition) needs the second.
--
-- Identifier namespaces in judge_id:
--   The judge pool built in scripts 03 and 08 concatenates three
--   registries into one text column without a namespace prefix:
--     - CourtListener people_db_person.id   (observed range 1-16,242)
--     - FJC fjc_judge_bio.nid               (observed range 1,376,976-13,762,122)
--     - supplemental judges                 ('sup_' || sup_id)
--   The numeric ranges do not overlap (verified: 0 colliding ids),
--   so the registry is recovered here by lookup against the source
--   tables rather than by a numeric threshold.
--
-- Output:
--   ext.author_person_resolved
--       One row per resolved opinion, with the resolved person
--       identifier where the match is unique.
--
-- Prerequisites:
--   09_create_final_gender_table.sql
-- ============================================================

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.author_person_resolved;

CREATE TABLE ext.author_person_resolved AS
WITH resolved AS (
    SELECT
        h.opinion_id,
        h.cluster_id,
        h.court_id,
        h.court_short_name,
        h.year_filed,
        h.gender,
        h.final_gender_assignment_channel AS channel,
        h.gender_match_quality_tier       AS tier,
        h.gender_match_quality_label      AS tier_label,
        h.author_id,

        -- Attribution step, per the four-stage cascade
        CASE
            WHEN h.final_gender_assignment_channel = 'previous_final'
                 AND h.gender_match_quality_tier = 1              THEN 1
            WHEN h.final_gender_assignment_channel = 'previous_final' THEN 2
            WHEN h.final_gender_assignment_channel = 'xml_author_tag' THEN 3
            WHEN h.final_gender_assignment_channel = 'html_extraction' THEN 4
        END AS attribution_step,

        -- Candidate count of the channel that produced the assignment
        CASE h.final_gender_assignment_channel
            WHEN 'previous_final'  THEN h.previous_final_n_candidate_judges
            WHEN 'xml_author_tag'  THEN h.xml_n_candidate_judges
            WHEN 'html_extraction' THEN h.html_n_candidate_judges
        END AS n_candidate_judges,

        -- Candidate identifier(s) of that same channel
        CASE h.final_gender_assignment_channel
            WHEN 'previous_final'  THEN f.candidate_nids
            WHEN 'xml_author_tag'  THEN t.xml_candidate_nids
            WHEN 'html_extraction' THEN t.html_candidate_nids
        END AS candidate_nids,

        CASE h.final_gender_assignment_channel
            WHEN 'previous_final'  THEN h.previous_final_candidate_names
            WHEN 'xml_author_tag'  THEN h.xml_candidate_names
            WHEN 'html_extraction' THEN h.html_candidate_names
        END AS candidate_names

    FROM ext.author_gender_final_with_html h
    LEFT JOIN ext.author_gender_final               f ON f.opinion_id = h.opinion_id
    LEFT JOIN ext.author_gender_from_text_extraction t ON t.opinion_id = h.opinion_id
    WHERE h.gender_resolved
),

flagged AS MATERIALIZED (
    SELECT
        r.*,
        -- Step 1 is unique by construction: it uses the explicit
        -- CourtListener author_id link, not name matching.
        CASE
            WHEN r.attribution_step = 1 AND r.author_id IS NOT NULL THEN TRUE
            WHEN r.n_candidate_judges = 1                          THEN TRUE
            ELSE FALSE
        END AS person_unique,

        CASE
            WHEN r.attribution_step = 1 AND r.author_id IS NOT NULL
                THEN r.author_id::text
            WHEN r.n_candidate_judges = 1
                THEN BTRIM(r.candidate_nids)
            ELSE NULL
        END AS judge_id
    FROM resolved r
),

-- Guarded numeric cast: 'sup_*' identifiers must never reach ::int,
-- so the cast is isolated in its own materialized step instead of
-- being written into a join condition (where the planner may
-- evaluate it before the regex guard).
flagged_num AS MATERIALIZED (
    SELECT
        fl.*,
        CASE WHEN fl.judge_id ~ '^[0-9]+$' THEN fl.judge_id::int END AS judge_id_num
    FROM flagged fl
)

SELECT
    fl.opinion_id,
    fl.cluster_id,
    fl.court_id,
    fl.court_short_name,
    fl.year_filed,
    fl.gender,
    fl.attribution_step,
    fl.channel,
    fl.tier,
    fl.tier_label,
    fl.n_candidate_judges,
    fl.person_unique,
    fl.judge_id,

    CASE
        WHEN fl.judge_id IS NULL             THEN NULL
        WHEN fl.judge_id LIKE 'sup\_%'       THEN 'supplemental'
        WHEN p.id  IS NOT NULL               THEN 'courtlistener_person'
        WHEN b.nid IS NOT NULL               THEN 'fjc_nid'
        ELSE 'unmapped'
    END AS id_registry,

    p.id  AS cl_person_id,
    b.nid AS fjc_nid,
    CASE WHEN fl.judge_id LIKE 'sup\_%'
         THEN SUBSTRING(fl.judge_id FROM 5)::int END AS sup_id,

    COALESCE(
        BTRIM(CONCAT_WS(' ', p.name_first, p.name_last)),
        BTRIM(CONCAT_WS(' ', b.first_name, b.last_name)),
        fl.candidate_names
    ) AS judge_display_name,

    fl.candidate_names

FROM flagged_num fl
LEFT JOIN public.people_db_person p ON p.id  = fl.judge_id_num
LEFT JOIN ext.fjc_judge_bio     b ON b.nid = fl.judge_id_num;

ALTER TABLE ext.author_person_resolved ADD PRIMARY KEY (opinion_id);

CREATE INDEX idx_apr_person_unique ON ext.author_person_resolved(person_unique);
CREATE INDEX idx_apr_judge_id      ON ext.author_person_resolved(judge_id);
CREATE INDEX idx_apr_step_tier     ON ext.author_person_resolved(attribution_step, tier);
CREATE INDEX idx_apr_court         ON ext.author_person_resolved(court_id);

COMMENT ON TABLE ext.author_person_resolved IS
'Resolved author attributions with a person_unique flag (exactly one candidate judge in the best matching tier) and the resolved judge identifier, mapped back to its source registry (CourtListener person, FJC nid, or supplemental).';

COMMIT;

ANALYZE ext.author_person_resolved;
