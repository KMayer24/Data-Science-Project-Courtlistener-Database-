-- ============================================================
-- 06_create_steps1_2_combined.sql
--
-- Purpose:
--   Combine Steps 1 and 2 into a single author-gender table
--   covering all Federal Appeals opinions.
--
--   Priority:
--     1. author_id match (Step 1)
--     2. author_str + unified judge pool match (Step 2)
--     3. unresolved
--
--   This table is the input for Steps 3 and 4 (text extraction).
--   Only opinions with gender_resolved = FALSE are passed forward.
--
-- Output:
--   ext.author_gender_final
--
-- Prerequisites:
--   01_create_author_gender_step1_author_id.sql
--   03_create_author_gender_step2_author_str.sql
-- ============================================================

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.author_gender_final;

CREATE TABLE ext.author_gender_final AS
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

    -- --------------------------------------------------------
    -- Final gender assignment
    -- Priority 1: structured author_id
    -- Priority 2: author_str + FJC
    -- Else: NULL
    -- --------------------------------------------------------

    CASE
        WHEN agid.gender_resolved THEN agid.gender
        WHEN ags.gender_resolved THEN ags.gender
        ELSE NULL
    END AS gender,

    CASE
        WHEN agid.gender_resolved THEN true
        WHEN ags.gender_resolved THEN true
        ELSE false
    END AS gender_resolved,

    CASE
        WHEN agid.gender_resolved THEN 'author_id'
        WHEN ags.gender_resolved THEN ags.gender_source

        WHEN fao.author_id IS NOT NULL
          AND COALESCE(agid.gender_resolved, false) = false
            THEN 'author_id_not_resolved'

        WHEN fao.author_id IS NULL
          AND fao.author_str IS NOT NULL
          AND TRIM(fao.author_str) <> ''
          AND ags.gender_source IS NOT NULL
            THEN ags.gender_source

        WHEN fao.author_id IS NULL
          AND (fao.author_str IS NULL OR TRIM(fao.author_str) = '')
            THEN 'no_author_id_or_author_str'

        ELSE 'unknown'
    END AS gender_source,

    -- --------------------------------------------------------
    -- Match-quality tier for easier filtering later
    -- --------------------------------------------------------

    CASE
        WHEN agid.gender_resolved
            THEN 1

        WHEN ags.gender_source = 'author_str_fjc_unique_judge'
          AND ags.gender_resolved
            THEN 2

        WHEN ags.gender_source = 'author_str_fjc_multiple_judges_same_gender'
          AND ags.gender_resolved
            THEN 4

        WHEN ags.gender_source = 'author_str_fjc_suffix_unique_gender'
          AND ags.gender_resolved
            THEN 3

        -- Any-court fallbacks (new in refactored Script 09)
        WHEN ags.gender_source IN (
                'author_str_any_court_unique_judge',
                'author_str_any_court_suffix_unique_judge')
          AND ags.gender_resolved
            THEN 5

        WHEN ags.gender_source IN (
                'author_str_any_court_unique_gender',
                'author_str_any_court_suffix_unique_gender')
          AND ags.gender_resolved
            THEN 6

        WHEN ags.gender_source = 'ambiguous_multiple_genders'
            THEN 8

        WHEN ags.gender_source = 'ambiguous_suffix_multiple_genders'
            THEN 8

        WHEN ags.gender_source IN ('no_fjc_match', 'no_match')
            THEN 9

        WHEN fao.author_id IS NULL
          AND (fao.author_str IS NULL OR TRIM(fao.author_str) = '')
            THEN 10

        ELSE 99
    END AS gender_match_quality_tier,

    CASE
        WHEN agid.gender_resolved
            THEN 'structured_author_id'

        WHEN ags.gender_source = 'author_str_fjc_unique_judge'
          AND ags.gender_resolved
            THEN 'exact_author_str_unique_judge'

        WHEN ags.gender_source = 'author_str_fjc_suffix_unique_gender'
          AND ags.gender_resolved
            THEN 'suffix_author_str_unique_gender'

        WHEN ags.gender_source = 'author_str_fjc_multiple_judges_same_gender'
          AND ags.gender_resolved
            THEN 'exact_author_str_multiple_judges_same_gender'

        WHEN ags.gender_source IN (
                'author_str_any_court_unique_judge',
                'author_str_any_court_suffix_unique_judge')
          AND ags.gender_resolved
            THEN 'any_court_author_str_unique_judge'

        WHEN ags.gender_source IN (
                'author_str_any_court_unique_gender',
                'author_str_any_court_suffix_unique_gender')
          AND ags.gender_resolved
            THEN 'any_court_author_str_unique_gender'

        WHEN ags.gender_source = 'ambiguous_multiple_genders'
            THEN 'ambiguous_multiple_genders'

        WHEN ags.gender_source = 'ambiguous_suffix_multiple_genders'
            THEN 'ambiguous_suffix_multiple_genders'

        WHEN ags.gender_source IN ('no_fjc_match', 'no_match')
            THEN 'no_fjc_match'

        WHEN fao.author_id IS NULL
          AND (fao.author_str IS NULL OR TRIM(fao.author_str) = '')
            THEN 'no_author_information'

        ELSE 'unknown'
    END AS gender_match_quality_label,

    -- --------------------------------------------------------
    -- Diagnostics from author_str-FJC matching
    -- These are NULL for author_id-only or no-author_str rows.
    -- --------------------------------------------------------

    ags.author_last_name_norm,
    ags.n_candidate_judges,
    ags.n_candidate_genders,
    ags.candidate_names,
    ags.candidate_nids

FROM ext.federal_appeal_opinions fao
LEFT JOIN ext.author_gender_author_id agid
    ON fao.opinion_id = agid.opinion_id
LEFT JOIN ext.author_gender_author_str_fjc ags
    ON fao.opinion_id = ags.opinion_id;

ALTER TABLE ext.author_gender_final
ADD PRIMARY KEY (opinion_id);

CREATE INDEX idx_author_gender_final_gender
    ON ext.author_gender_final(gender);

CREATE INDEX idx_author_gender_final_gender_resolved
    ON ext.author_gender_final(gender_resolved);

CREATE INDEX idx_author_gender_final_gender_source
    ON ext.author_gender_final(gender_source);

CREATE INDEX idx_author_gender_final_quality_tier
    ON ext.author_gender_final(gender_match_quality_tier);

CREATE INDEX idx_author_gender_final_court_id
    ON ext.author_gender_final(court_id);

CREATE INDEX idx_author_gender_final_year
    ON ext.author_gender_final(year_filed);

CREATE INDEX idx_author_gender_final_author_str
    ON ext.author_gender_final(author_str);

COMMIT;