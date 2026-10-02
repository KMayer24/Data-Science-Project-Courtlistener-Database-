-- ============================================================
-- 09_create_final_gender_table.sql
--
-- Purpose:
--   Assemble the definitive author-gender table for all Federal
--   Appeals opinions by combining all four resolution steps.
--
--   Priority:
--     1. author_id match (Step 1)
--     2. author_str + unified judge pool match (Step 2)
--     3. XML <author> tag + judge pool match (Step 3)
--     4. HTML body text extraction + judge pool match (Step 4)
--
--   Text-extraction gender (Steps 3+4) is only used when Steps
--   1+2 both failed. Within text extraction, XML has priority
--   over HTML. All diagnostic columns are preserved.
--
-- Output:
--   ext.author_gender_final_with_html
--       One row per opinion in ext.federal_appeal_opinions.
--
-- Prerequisites:
--   06_create_steps1_2_combined.sql
--   08_create_steps3_4_text_extraction.sql
-- ============================================================

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.author_gender_final_with_html;

CREATE TABLE ext.author_gender_final_with_html AS
SELECT
    fao.opinion_id,
    fao.cluster_id,
    fao.docket_id,
    fao.court_id,
    fao.court_short_name,
    fao.date_filed,
    fao.year_filed,
    fao.case_name,
    fao.opinion_type,
    fao.precedential_status,
    fao.per_curiam,

    fao.author_id,
    fao.author_str,

    -- --------------------------------------------------------
    -- Final gender assignment
    -- Priority 1+2: previous final (author_id / author_str / judge-reference match)
    -- Priority 3:   XML <author> tag + judge-reference match
    -- Priority 4:   html_with_citations extraction + judge-reference match
    -- Else:         unresolved
    -- --------------------------------------------------------
    CASE
        WHEN COALESCE(f.gender_resolved,      FALSE) = TRUE THEN f.gender
        WHEN COALESCE(t.xml_gender_resolved,  FALSE) = TRUE THEN t.xml_gender
        WHEN COALESCE(t.html_gender_resolved, FALSE) = TRUE THEN t.html_gender
        ELSE NULL
    END AS gender,

    CASE
        WHEN COALESCE(f.gender_resolved,      FALSE) = TRUE THEN TRUE
        WHEN COALESCE(t.xml_gender_resolved,  FALSE) = TRUE THEN TRUE
        WHEN COALESCE(t.html_gender_resolved, FALSE) = TRUE THEN TRUE
        ELSE FALSE
    END AS gender_resolved,

    CASE
        WHEN COALESCE(f.gender_resolved,      FALSE) = TRUE THEN f.gender_source
        WHEN COALESCE(t.xml_gender_resolved,  FALSE) = TRUE THEN t.xml_gender_source
        WHEN COALESCE(t.html_gender_resolved, FALSE) = TRUE THEN t.html_gender_source
        WHEN f.gender_source              IS NOT NULL       THEN f.gender_source
        WHEN t.xml_gender_source          IS NOT NULL       THEN t.xml_gender_source
        WHEN t.html_gender_source         IS NOT NULL       THEN t.html_gender_source
        WHEN fao.author_id IS NULL
          AND (fao.author_str IS NULL OR BTRIM(fao.author_str) = '')
            THEN 'no_author_id_or_author_str'
        ELSE 'unknown'
    END AS gender_source,

    CASE
        WHEN COALESCE(f.gender_resolved,      FALSE) = TRUE THEN f.gender_match_quality_tier
        WHEN COALESCE(t.xml_gender_resolved,  FALSE) = TRUE THEN t.xml_gender_match_quality_tier
        WHEN COALESCE(t.html_gender_resolved, FALSE) = TRUE THEN t.html_gender_match_quality_tier
        WHEN f.gender_match_quality_tier          IS NOT NULL THEN f.gender_match_quality_tier
        WHEN t.xml_gender_match_quality_tier      IS NOT NULL THEN t.xml_gender_match_quality_tier
        WHEN t.html_gender_match_quality_tier     IS NOT NULL THEN t.html_gender_match_quality_tier
        WHEN fao.author_id IS NULL
          AND (fao.author_str IS NULL OR BTRIM(fao.author_str) = '')
            THEN 10
        ELSE 99
    END AS gender_match_quality_tier,

    CASE
        WHEN COALESCE(f.gender_resolved,      FALSE) = TRUE THEN f.gender_match_quality_label
        WHEN COALESCE(t.xml_gender_resolved,  FALSE) = TRUE THEN t.xml_gender_match_quality_label
        WHEN COALESCE(t.html_gender_resolved, FALSE) = TRUE THEN t.html_gender_match_quality_label
        WHEN f.gender_match_quality_label         IS NOT NULL THEN f.gender_match_quality_label
        WHEN t.xml_gender_match_quality_label     IS NOT NULL THEN t.xml_gender_match_quality_label
        WHEN t.html_gender_match_quality_label    IS NOT NULL THEN t.html_gender_match_quality_label
        WHEN fao.author_id IS NULL
          AND (fao.author_str IS NULL OR BTRIM(fao.author_str) = '')
            THEN 'no_author_information'
        ELSE 'unknown'
    END AS gender_match_quality_label,

    -- --------------------------------------------------------
    -- Source channel flag
    -- --------------------------------------------------------
    CASE
        WHEN COALESCE(f.gender_resolved,      FALSE) = TRUE THEN 'previous_final'
        WHEN COALESCE(t.xml_gender_resolved,  FALSE) = TRUE THEN 'xml_author_tag'
        WHEN COALESCE(t.html_gender_resolved, FALSE) = TRUE THEN 'html_extraction'
        ELSE 'unresolved'
    END AS final_gender_assignment_channel,

    CASE
        WHEN COALESCE(f.gender_resolved,      FALSE) = TRUE THEN 1
        WHEN COALESCE(t.xml_gender_resolved,  FALSE) = TRUE THEN 2
        WHEN COALESCE(t.html_gender_resolved, FALSE) = TRUE THEN 3
        ELSE 99
    END AS final_gender_assignment_priority,

    -- --------------------------------------------------------
    -- Prio-1+2 diagnostics (author_id / author_str / judge-reference match)
    -- --------------------------------------------------------
    f.gender                              AS previous_final_gender,
    COALESCE(f.gender_resolved, FALSE)    AS previous_final_gender_resolved,
    f.gender_source                       AS previous_final_gender_source,
    f.gender_match_quality_tier           AS previous_final_gender_match_quality_tier,
    f.gender_match_quality_label          AS previous_final_gender_match_quality_label,
    f.author_last_name_norm               AS previous_final_author_last_name_norm,
    f.n_candidate_judges                  AS previous_final_n_candidate_judges,
    f.n_candidate_genders                 AS previous_final_n_candidate_genders,
    f.candidate_names                     AS previous_final_candidate_names,

    -- --------------------------------------------------------
    -- Prio-3 diagnostics (XML <author> tag)
    -- --------------------------------------------------------
    t.xml_gender,
    COALESCE(t.xml_gender_resolved, FALSE) AS xml_gender_resolved,
    t.xml_gender_source,
    t.xml_gender_match_quality_tier,
    t.xml_gender_match_quality_label,
    t.xml_raw_author_tag,
    t.xml_clean_author_tag,
    t.xml_extracted_author_name,
    t.xml_extracted_author_last_name_norm,
    t.xml_n_candidate_judges,
    t.xml_n_candidate_genders,
    t.xml_candidate_names,

    -- --------------------------------------------------------
    -- Prio-4 diagnostics (HTML body extraction)
    -- --------------------------------------------------------
    t.html_gender,
    COALESCE(t.html_gender_resolved, FALSE) AS html_gender_resolved,
    t.html_gender_source,
    t.html_gender_match_quality_tier,
    t.html_gender_match_quality_label,
    t.html_type                             AS html_html_type,
    t.html_extraction_pattern               AS html_extraction_pattern,
    t.html_extracted_author_name,
    t.html_extracted_author_last_name_norm,
    t.html_n_candidate_judges,
    t.html_n_candidate_genders,
    t.html_candidate_names

FROM ext.federal_appeal_opinions fao
LEFT JOIN ext.author_gender_final f
    ON f.opinion_id = fao.opinion_id
LEFT JOIN ext.author_gender_from_text_extraction t
    ON t.opinion_id = fao.opinion_id;

ALTER TABLE ext.author_gender_final_with_html
ADD PRIMARY KEY (opinion_id);

CREATE INDEX idx_author_gender_final_with_html_gender
    ON ext.author_gender_final_with_html(gender);

CREATE INDEX idx_author_gender_final_with_html_gender_resolved
    ON ext.author_gender_final_with_html(gender_resolved);

CREATE INDEX idx_author_gender_final_with_html_gender_source
    ON ext.author_gender_final_with_html(gender_source);

CREATE INDEX idx_author_gender_final_with_html_quality_tier
    ON ext.author_gender_final_with_html(gender_match_quality_tier);

CREATE INDEX idx_author_gender_final_with_html_channel
    ON ext.author_gender_final_with_html(final_gender_assignment_channel);

CREATE INDEX idx_author_gender_final_with_html_priority
    ON ext.author_gender_final_with_html(final_gender_assignment_priority);

CREATE INDEX idx_author_gender_final_with_html_court_id
    ON ext.author_gender_final_with_html(court_id);

CREATE INDEX idx_author_gender_final_with_html_year
    ON ext.author_gender_final_with_html(year_filed);

CREATE INDEX idx_author_gender_final_with_html_opinion_type
    ON ext.author_gender_final_with_html(opinion_type);

CREATE INDEX idx_author_gender_final_with_html_author_str
    ON ext.author_gender_final_with_html(author_str);

CREATE INDEX idx_author_gender_final_with_html_html_pattern
    ON ext.author_gender_final_with_html(html_extraction_pattern);

ANALYZE ext.author_gender_final_with_html;

COMMIT;