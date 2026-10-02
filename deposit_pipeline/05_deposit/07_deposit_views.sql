-- ============================================================
-- 07_deposit_views.sql
--
-- Purpose:
--   Define the deposit-facing version of the derived layer as a schema
--   of VIEWS. Nothing in ext is renamed or moved; the deposit reads through
--   this schema and exposes stable publication-facing names.
--
-- What the deposit leaves out, and why:
--   ext.federal_appeal_opinions        17 GB of opinion text that is
--                                      already in public.search_opinion.
--                                      The metadata twin is deposited.
--   ext.author_gender_final            intermediate stage; every column
--                                      survives in the final table.
--   ext.opinion_legal_domain           no build script, and 42 % of rows
--                                      carry neither domain nor source.
--   ext.federal_appeals_opinion_header_text
--                                      materialised view, no build
--                                      script, derivable from the text.
--
-- What is renamed (in the deposit only):
--   author_gender_final_with_html -> opinion_author_attribution
--                                    (+ a separate diagnostics table)
--   rq2_domain                    -> case_domain
--   fjc_* judge tables            -> neutral judge_* names
--
-- What is deposited unchanged:
--   the two FJC appellate raw snapshots -- they are provenance, they are
--   small, and the upstream files change over time.
--
-- ext.author_party_resolved is NOT deposited, although its lost build
-- script was reconstructed and verified (04/05). It merges two distinct
-- party concepts into one column and dates the recorded affiliation by
-- last record rather than by filing date. The deposit uses
-- ext.author_party_timeaware (08) instead, which separates the two
-- measures and resolves the affiliation at the filing date. The old
-- table remains available only as a legacy comparison input.
-- ============================================================

\pset pager off

BEGIN;

DROP SCHEMA IF EXISTS deposit CASCADE;
CREATE SCHEMA deposit;

COMMENT ON SCHEMA deposit IS
'Deposit-facing presentation of the derived layer: neutral table and column names, internal intermediates omitted. Views only.';

-- ---------------------------------------------------------------
-- 1. Court universe
-- ---------------------------------------------------------------
CREATE VIEW deposit.appellate_court AS
SELECT id AS court_id, short_name, full_name, jurisdiction, inclusion_reason
FROM ext.federal_appeal_courts;

CREATE VIEW deposit.appellate_court_excluded AS
SELECT id AS court_id, short_name, full_name, jurisdiction,
       exclusion_category, exclusion_reason
FROM ext.excluded_appeals_named_courts;

-- ---------------------------------------------------------------
-- 2. Opinion metadata (no text: see public.search_opinion)
-- ---------------------------------------------------------------
CREATE VIEW deposit.appellate_opinion AS
SELECT * FROM ext.federal_appeal_opinion_meta;

-- ---------------------------------------------------------------
-- 3. Judge reference set
-- ---------------------------------------------------------------
CREATE VIEW deposit.judge_biography AS
SELECT nid AS judge_nid, jid, last_name, first_name, middle_name, suffix,
       gender, race_or_ethnicity
FROM ext.fjc_judge_bio;

CREATE VIEW deposit.judge_service AS
SELECT id AS service_id, nid AS judge_nid, appointment_seq, judge_name,
       court_type, court_name, appointment_title,
       appointing_president, party_of_appointing_president,
       commission_date, termination, termination_date
FROM ext.fjc_judge_court;

CREATE VIEW deposit.judge_court_name_map AS
SELECT court_id, court_short_name, court_full_name,
       fjc_court_name, mapping_note
FROM ext.fjc_court_name_map;

CREATE VIEW deposit.judge_supplemental AS
SELECT sup_id AS supplemental_id, name_first, name_middle, name_last,
       gender, court_id, start_date, end_date, reason
FROM ext.supplemental_judges;

-- ---------------------------------------------------------------
-- 4. Author attribution -- lean table
--
-- One row per appellate opinion, resolved or not. The 53-column
-- working table is split: the columns a user needs to filter and join
-- on stay here, the per-stage evidence moves to the diagnostics view.
-- ---------------------------------------------------------------
CREATE VIEW deposit.opinion_author_attribution AS
SELECT
    h.opinion_id,
    h.cluster_id,
    h.docket_id,
    h.court_id,
    h.date_filed,
    h.year_filed,
    h.opinion_type,
    h.precedential_status,
    h.per_curiam,

    h.gender,
    h.gender_resolved,

    r.attribution_step,
    h.gender_match_quality_tier  AS match_tier,
    h.gender_match_quality_label AS match_tier_label,
    r.n_candidate_judges,

    -- TRUE only when the match identifies exactly one judge. Gender
    -- resolution is weaker: it also holds when several candidates share
    -- the recorded gender.
    COALESCE(r.person_unique, FALSE) AS person_unique,
    r.judge_id,
    r.id_registry,
    r.cl_person_id,
    r.fjc_nid,
    r.judge_display_name
FROM ext.author_gender_final_with_html h
LEFT JOIN ext.author_person_resolved r USING (opinion_id);

COMMENT ON VIEW deposit.opinion_author_attribution IS
'One row per federal appellate opinion. gender_resolved means all candidates in the best matching tier agreed on gender; person_unique means the match identified a single judge. Gender is inherited from recorded biographical data, never inferred from names or text.';

-- ---------------------------------------------------------------
-- 5. Author attribution -- per-stage diagnostics
-- ---------------------------------------------------------------
CREATE VIEW deposit.opinion_author_attribution_diagnostics AS
SELECT
    opinion_id,
    author_id                                 AS courtlistener_author_id,
    author_str                                AS recorded_author_string,
    final_gender_assignment_channel           AS assignment_channel,

    previous_final_gender                     AS name_stage_gender,
    previous_final_gender_source              AS name_stage_source,
    previous_final_gender_match_quality_tier  AS name_stage_tier,
    previous_final_author_last_name_norm      AS name_stage_surname_norm,
    previous_final_n_candidate_judges         AS name_stage_n_candidates,
    previous_final_candidate_names            AS name_stage_candidates,

    xml_gender                                AS xml_stage_gender,
    xml_gender_source                         AS xml_stage_source,
    xml_gender_match_quality_tier             AS xml_stage_tier,
    xml_clean_author_tag                      AS xml_stage_author_tag,
    xml_extracted_author_name                 AS xml_stage_extracted_name,
    xml_n_candidate_judges                    AS xml_stage_n_candidates,
    xml_candidate_names                       AS xml_stage_candidates,

    html_gender                               AS html_stage_gender,
    html_gender_source                        AS html_stage_source,
    html_gender_match_quality_tier            AS html_stage_tier,
    html_html_type                            AS html_stage_source_format,
    html_extraction_pattern                   AS html_stage_pattern,
    html_extracted_author_name                AS html_stage_extracted_name,
    html_n_candidate_judges                   AS html_stage_n_candidates,
    html_candidate_names                      AS html_stage_candidates
FROM ext.author_gender_final_with_html;

-- ---------------------------------------------------------------
-- 6. Author political party
--
-- The two measures are deliberately NOT merged. Party of the appointing
-- president and the judge's own recorded affiliation answer different
-- questions and have very different coverage. party_convenience exists
-- only so that a user who genuinely wants "some party" does not have to
-- write the COALESCE themselves; it is derived, not measured.
--
-- Source: ext.author_party_timeaware (sql/derived/08), which resolves
-- the recorded affiliation as of the filing date. The older
-- ext.author_party_resolved is not deposited: it merged the two
-- measures into one column and used the most recently recorded
-- affiliation regardless of filing date.
-- ---------------------------------------------------------------
CREATE VIEW deposit.opinion_author_party AS
SELECT
    opinion_id,
    court_id,
    date_filed,
    year_filed,
    judge_id,
    cl_person_id,
    fjc_nid,

    -- Measure 1
    appointing_president_party,
    appointing_match_quality,

    -- Measure 2, as of the filing date
    registered_party,
    registered_party_code,
    registered_party_resolution,
    registered_n_records,
    registered_period_start,
    registered_period_end,

    -- Derived convenience only
    party_convenience,
    party_convenience_source
FROM ext.author_party_timeaware;

COMMENT ON VIEW deposit.opinion_author_party IS
'Two separate party measures per attributed opinion: the appointing president''s party, and the judge''s own recorded affiliation as it stood on the filing date (registered_party_resolution says how it was determined). party_convenience is a derived fallback column, not an independent measurement.';

-- ---------------------------------------------------------------
-- 7. FJC appellate case records
-- ---------------------------------------------------------------
CREATE VIEW deposit.fjc_appellate_raw_1971to2007 AS
SELECT * FROM ext.fjc_appellate_raw_1971to2007;

CREATE VIEW deposit.fjc_appellate_raw_2008plus AS
SELECT * FROM ext.fjc_appellate_raw_2008plus;

CREATE VIEW deposit.fjc_appellate_case AS
SELECT * FROM ext.fjc_appellate_normalized;

CREATE VIEW deposit.opinion_fjc_match AS
SELECT * FROM ext.fjc_opinion_match;

CREATE VIEW deposit.opinion_case_covariates AS
SELECT
    opinion_id, cluster_id, court_id, opinion_date, year_filed, decade,
    match_tier, date_diff_days, was_ambiguous, fjc_appeal_id,
    case_class, is_civil,
    rq2_domain AS case_domain,
    appeal_type_code, nature_of_suit_code, offense_code, agency_code,
    jurisdiction_code, outcome_code, outcome_label, outcome_class,
    disposition_code, disposition_label, analysis_eligible
FROM ext.opinion_fjc_covariates;

-- ---------------------------------------------------------------
-- 8. Crosswalks
-- ---------------------------------------------------------------
CREATE VIEW deposit.crosswalk_case_domain AS
SELECT code_kind, code_value, rq2_domain AS case_domain, note
FROM ext.fjc_domain_crosswalk;

CREATE VIEW deposit.crosswalk_outcome AS
SELECT outcome_code, outcome_label, outcome_class FROM ext.fjc_outcome_crosswalk;

CREATE VIEW deposit.crosswalk_disposition AS
SELECT disposition_code, disposition_label FROM ext.fjc_disposition_crosswalk;

COMMIT;

\echo ''
\echo 'Deposit views created. Row counts:'
SELECT table_name FROM information_schema.views
WHERE table_schema = 'deposit' ORDER BY table_name;
