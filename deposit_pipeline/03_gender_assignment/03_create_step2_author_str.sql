-- ============================================================
-- 03_create_author_gender_step2_author_str.sql
--
-- Purpose:
--   Resolve author gender for Federal Appeals opinions using
--   unstructured CourtListener author_str matched against a
--   unified judge pool (Step 2).
--
--   Applied only to opinions without a structured author_id.
--
-- Method:
--   ext.federal_appeal_opinions.author_str
--       -> cleaned last-name candidate
--       + court_id
--       -> unified judge pool (CourtListener + FJC + Supplemental)
--
--   Match priority:
--     1. Exact last-name match, same circuit
--     2. Compound-name suffix match, same circuit
--        (e.g. "orsdel" matches "van orsdel")
--     3. Exact last-name match, any circuit
--     4. Compound-name suffix match, any circuit
--
--   Gender is assigned only when all candidates at the best
--   available tier share the same gender.
--
-- Output:
--   ext.author_gender_author_str_fjc
--
-- Prerequisites:
--   01_create_fjc_judge_tables.sql
--   03_create_fjc_court_name_map.sql
--   04_create_supplemental_judges.sql
-- ============================================================

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.author_gender_author_str_fjc;

-- ------------------------------------------------------------
-- 1. Create author_str-based FJC gender mapping table
-- ------------------------------------------------------------

CREATE TABLE ext.author_gender_author_str_fjc AS
WITH opinions_to_match AS (
    SELECT
        fao.opinion_id,
        fao.cluster_id,
        fao.docket_id,
        fao.court_id,
        fao.court_short_name,
        fao.date_filed,
        fao.year_filed,
        fao.case_name,

        fao.author_id,
        fao.author_str,

        -- Clean unstructured CourtListener author string.
        -- Important: keep multi-word surnames instead of taking only
        -- the first token. This avoids errors like:
        --   "Van Oosterhout"  -> "van"
        --   "De Brorby"       -> "de"
        --   "St.Eve"          -> "steve"
        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    COALESCE(fao.author_str, ''),
                                    '^(by|opinion by|judge|justice)\s+',
                                    '',
                                    'i'
                                ),
                                '\s*,.*$',
                                '',
                                'g'
                            ),
                            '\.',
                            ' ',
                            'g'
                        ),
                        '[^A-Za-z\-\s'']',
                        '',
                        'g'
                    ),
                    '\s+',
                    ' ',
                    'g'
                )
            )
        ) AS author_last_name_norm

    FROM ext.federal_appeal_opinions fao
    WHERE fao.author_id IS NULL
      AND fao.per_curiam = FALSE
      AND fao.author_str IS NOT NULL
      AND TRIM(fao.author_str) <> ''
),

-- ------------------------------------------------------------
-- 2. Unified judge pool: CourtListener + FJC + Supplemental
--    (same space-preserving normalization as opinions_to_match)
-- ------------------------------------------------------------

all_appeals_judges AS (
    -- Primary: CourtListener people_db (covers post-2012 appointees)
    SELECT DISTINCT
        pos.court_id,
        p.id::text                                                          AS judge_id,
        BTRIM(CONCAT_WS(' ',
            NULLIF(BTRIM(COALESCE(p.name_first, '')), ''),
            NULLIF(BTRIM(COALESCE(p.name_last,  '')), '')))                 AS display_name,
        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(p.name_last, ''),
                            '\.', ' ', 'g'),
                        '[^A-Za-z\-\s'']', '', 'g'),
                    '\s+', ' ', 'g')
            )
        )                                                                   AS last_name_norm,
        (REGEXP_MATCH(
            LOWER(TRIM(REGEXP_REPLACE(REGEXP_REPLACE(REGEXP_REPLACE(
                COALESCE(p.name_last, ''),
                '\.', ' ', 'g'), '[^A-Za-z\-\s'']', '', 'g'), '\s+', ' ', 'g'))),
            '([^ ]+)$'))[1]                                                 AS last_name_final_token,
        p.gender
    FROM people_db_person p
    JOIN people_db_position pos ON pos.person_id = p.id
    WHERE p.gender IN ('m', 'f')
      AND pos.court_id IN ('ca1','ca2','ca3','ca4','ca5','ca6',
                           'ca7','ca8','ca9','ca10','ca11','cafc','cadc')
      AND pos.position_type IN ('jud', 'ret-senior-jud', 'c-jus')
      AND p.name_last IS NOT NULL AND TRIM(p.name_last) <> ''

    UNION ALL

    -- Fallback: FJC (judges not already covered by CL with gender)
    SELECT DISTINCT
        m.court_id,
        b.nid::text                                                         AS judge_id,
        BTRIM(CONCAT_WS(' ', b.first_name, b.last_name))                   AS display_name,
        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(b.last_name, ''),
                            '\.', ' ', 'g'),
                        '[^A-Za-z\-\s'']', '', 'g'),
                    '\s+', ' ', 'g')
            )
        )                                                                   AS last_name_norm,
        (REGEXP_MATCH(
            LOWER(TRIM(REGEXP_REPLACE(REGEXP_REPLACE(REGEXP_REPLACE(
                COALESCE(b.last_name, ''),
                '\.', ' ', 'g'), '[^A-Za-z\-\s'']', '', 'g'), '\s+', ' ', 'g'))),
            '([^ ]+)$'))[1]                                                 AS last_name_final_token,
        b.gender
    FROM ext.fjc_judge_court jc
    JOIN ext.fjc_judge_bio b ON jc.nid = b.nid
    JOIN ext.fjc_court_name_map m ON jc.court_name = m.fjc_court_name
    WHERE jc.court_type = 'U.S. Court of Appeals'
      AND b.gender IN ('m', 'f')
      AND b.last_name IS NOT NULL AND TRIM(b.last_name) <> ''
      AND NOT EXISTS (
          SELECT 1 FROM people_db_person p
          JOIN people_db_position pos2 ON pos2.person_id = p.id
          WHERE p.fjc_id = b.jid
            AND p.gender IN ('m', 'f')
            AND pos2.court_id = m.court_id
            AND pos2.position_type IN ('jud', 'ret-senior-jud', 'c-jus')
      )

    UNION ALL

    -- Supplemental: manually curated judges
    SELECT DISTINCT
        s.court_id,
        'sup_' || s.sup_id::text                                            AS judge_id,
        BTRIM(CONCAT_WS(' ',
            NULLIF(BTRIM(COALESCE(s.name_first, '')), ''),
            NULLIF(BTRIM(COALESCE(s.name_last,  '')), '')))                 AS display_name,
        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(s.name_last, ''),
                            '\.', ' ', 'g'),
                        '[^A-Za-z\-\s'']', '', 'g'),
                    '\s+', ' ', 'g')
            )
        )                                                                   AS last_name_norm,
        (REGEXP_MATCH(
            LOWER(TRIM(REGEXP_REPLACE(REGEXP_REPLACE(REGEXP_REPLACE(
                COALESCE(s.name_last, ''),
                '\.', ' ', 'g'), '[^A-Za-z\-\s'']', '', 'g'), '\s+', ' ', 'g'))),
            '([^ ]+)$'))[1]                                                 AS last_name_final_token,
        s.gender
    FROM ext.supplemental_judges s
    WHERE s.name_last IS NOT NULL AND TRIM(s.name_last) <> ''
),

-- ------------------------------------------------------------
-- 3. Candidate matches with priority tiers
--
-- Priority 1: exact last-name match + same circuit
-- Priority 2: compound-name suffix match + same circuit
--             (e.g. author_str="orsdel" matches "van orsdel")
-- Priority 3: exact last-name match across ALL circuits
--             (catches by-designation / visiting judges)
-- Priority 4: compound-name suffix match across ALL circuits
-- ------------------------------------------------------------

candidate_matches AS (
    SELECT
        o.opinion_id,
        f.judge_id,
        f.gender,
        f.display_name,
        f.court_id,

        CASE
            WHEN o.author_last_name_norm = f.last_name_norm
             AND o.court_id = f.court_id
                THEN 'exact_same_court'

            WHEN o.author_last_name_norm = f.last_name_final_token
             AND o.author_last_name_norm <> f.last_name_norm
             AND o.court_id = f.court_id
                THEN 'suffix_same_court'

            WHEN o.author_last_name_norm = f.last_name_norm
                THEN 'exact_any_court'

            WHEN o.author_last_name_norm = f.last_name_final_token
             AND o.author_last_name_norm <> f.last_name_norm
                THEN 'suffix_any_court'

            ELSE NULL
        END AS match_type

    FROM opinions_to_match o
    JOIN all_appeals_judges f
        ON (o.author_last_name_norm = f.last_name_norm
            OR (o.author_last_name_norm = f.last_name_final_token
                AND o.author_last_name_norm <> f.last_name_norm))
    WHERE o.author_last_name_norm IS NOT NULL
      AND TRIM(o.author_last_name_norm) <> ''
),

ranked AS (
    SELECT *,
        CASE match_type
            WHEN 'exact_same_court'  THEN 1
            WHEN 'suffix_same_court' THEN 2
            WHEN 'exact_any_court'   THEN 3
            WHEN 'suffix_any_court'  THEN 4
            ELSE 99
        END AS match_priority
    FROM candidate_matches
    WHERE match_type IS NOT NULL
),

best_priority AS (
    SELECT opinion_id, MIN(match_priority) AS best_match_priority
    FROM ranked
    GROUP BY opinion_id
),

best_candidates AS (
    SELECT r.*
    FROM ranked r
    JOIN best_priority bp
        ON bp.opinion_id = r.opinion_id
       AND bp.best_match_priority = r.match_priority
),

aggregated_matches AS (
    SELECT
        opinion_id,
        MIN(match_priority)                                             AS best_match_priority,
        COUNT(DISTINCT judge_id)                                        AS n_candidate_judges,
        COUNT(DISTINCT gender)
            FILTER (WHERE gender IS NOT NULL AND BTRIM(gender) <> '')  AS n_candidate_genders,
        MIN(gender)
            FILTER (WHERE gender IS NOT NULL AND BTRIM(gender) <> '')  AS gender_if_unique,
        STRING_AGG(DISTINCT display_name, '; ' ORDER BY display_name)  AS candidate_names,
        STRING_AGG(DISTINCT judge_id,     '; ' ORDER BY judge_id)      AS candidate_nids
    FROM best_candidates
    GROUP BY opinion_id
)

SELECT
    o.opinion_id,
    o.cluster_id,
    o.docket_id,
    o.court_id,
    o.court_short_name,
    o.date_filed,
    o.year_filed,
    o.case_name,

    o.author_id,
    o.author_str,
    o.author_last_name_norm,

    COALESCE(am.n_candidate_judges,  0) AS n_candidate_judges,
    COALESCE(am.n_candidate_genders, 0) AS n_candidate_genders,
    am.candidate_names,
    am.candidate_nids,

    CASE
        WHEN o.author_last_name_norm IS NULL
          OR TRIM(o.author_last_name_norm) = ''
            THEN NULL
        WHEN am.n_candidate_genders = 1
            THEN am.gender_if_unique
        ELSE NULL
    END AS gender,

    CASE
        WHEN o.author_last_name_norm IS NULL
          OR TRIM(o.author_last_name_norm) = ''
            THEN 'no_usable_author_str'

        WHEN am.best_match_priority = 1 AND am.n_candidate_judges = 1 AND am.n_candidate_genders = 1
            THEN 'author_str_fjc_unique_judge'

        WHEN am.best_match_priority = 1 AND am.n_candidate_genders = 1
            THEN 'author_str_fjc_multiple_judges_same_gender'

        WHEN am.best_match_priority = 1 AND am.n_candidate_genders > 1
            THEN 'ambiguous_multiple_genders'

        WHEN am.best_match_priority = 2 AND am.n_candidate_judges = 1 AND am.n_candidate_genders = 1
            THEN 'author_str_fjc_suffix_unique_gender'

        WHEN am.best_match_priority = 2 AND am.n_candidate_genders = 1
            THEN 'author_str_fjc_suffix_unique_gender'

        WHEN am.best_match_priority = 2 AND am.n_candidate_genders > 1
            THEN 'ambiguous_suffix_multiple_genders'

        WHEN am.best_match_priority = 3 AND am.n_candidate_judges = 1 AND am.n_candidate_genders = 1
            THEN 'author_str_any_court_unique_judge'

        WHEN am.best_match_priority = 3 AND am.n_candidate_genders = 1
            THEN 'author_str_any_court_unique_gender'

        WHEN am.best_match_priority = 3 AND am.n_candidate_genders > 1
            THEN 'ambiguous_multiple_genders'

        WHEN am.best_match_priority = 4 AND am.n_candidate_judges = 1 AND am.n_candidate_genders = 1
            THEN 'author_str_any_court_suffix_unique_judge'

        WHEN am.best_match_priority = 4 AND am.n_candidate_genders = 1
            THEN 'author_str_any_court_suffix_unique_gender'

        WHEN am.best_match_priority = 4 AND am.n_candidate_genders > 1
            THEN 'ambiguous_suffix_multiple_genders'

        WHEN COALESCE(am.n_candidate_judges, 0) = 0
            THEN 'no_fjc_match'

        ELSE 'unknown'
    END AS gender_source,

    CASE
        WHEN am.n_candidate_genders = 1 THEN true
        ELSE false
    END AS gender_resolved

FROM opinions_to_match o
LEFT JOIN aggregated_matches am ON am.opinion_id = o.opinion_id;

ALTER TABLE ext.author_gender_author_str_fjc
ADD PRIMARY KEY (opinion_id);

CREATE INDEX idx_author_gender_author_str_fjc_court_id
    ON ext.author_gender_author_str_fjc(court_id);

CREATE INDEX idx_author_gender_author_str_fjc_gender
    ON ext.author_gender_author_str_fjc(gender);

CREATE INDEX idx_author_gender_author_str_fjc_gender_source
    ON ext.author_gender_author_str_fjc(gender_source);

CREATE INDEX idx_author_gender_author_str_fjc_last_name
    ON ext.author_gender_author_str_fjc(author_last_name_norm);

CREATE INDEX idx_author_gender_author_str_fjc_year
    ON ext.author_gender_author_str_fjc(year_filed);

COMMIT;