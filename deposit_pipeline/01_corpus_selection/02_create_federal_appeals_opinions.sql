-- ============================================================
-- 02_create_federal_appeals_opinions.sql
--
-- Purpose:
--   Create the opinion-level analysis table for the Federal
--   Appeals corpus.
--
-- Prerequisite:
--   01_federal_appeals_subset.sql (ext.federal_appeal_courts)
--
-- Output:
--   ext.federal_appeal_opinions
--       Full opinion-level subset including text fields.
--
--   ext.federal_appeal_opinion_meta
--       Metadata-only subset excluding large text fields.
--
-- Text fields:
--   html_with_citations  CourtListener's preferred text field,
--                        with identified and linked citations.
--   plain_text           Plain text version; less consistently
--                        populated, not used as primary source.
--
-- Nature of suit:
--   Two variables are retained (cluster and docket level) so
--   their coverage and consistency can be checked separately.
--
-- This script does not modify original CourtListener tables.
-- ============================================================

\pset pager off
\timing on

BEGIN;

CREATE SCHEMA IF NOT EXISTS ext;

-- ------------------------------------------------------------
-- 1. Remove previous subset tables, if they exist
-- ------------------------------------------------------------

DROP TABLE IF EXISTS ext.federal_appeal_opinion_meta;
DROP TABLE IF EXISTS ext.federal_appeal_opinions;


-- ------------------------------------------------------------
-- 2. Create full opinion-level subset including text fields
-- ------------------------------------------------------------

CREATE TABLE ext.federal_appeal_opinions AS
SELECT
    o.id AS opinion_id,
    o.cluster_id,
    oc.docket_id,
    d.court_id,

    c.short_name AS court_short_name,
    c.full_name AS court_full_name,

    oc.date_filed,
    EXTRACT(YEAR FROM oc.date_filed)::integer AS year_filed,

    oc.case_name,
    oc.case_name_full,
    oc.precedential_status,
    oc.citation_count,
    oc.nature_of_suit AS cluster_nature_of_suit,

    d.docket_number,
    d.docket_number_core,
    d.nature_of_suit AS docket_nature_of_suit,
    d.cause AS docket_cause,
    d.jurisdiction_type AS docket_jurisdiction_type,

    o.author_id,
    o.author_str,
    o.type AS opinion_type,
    o.per_curiam,
    o.page_count,

    -- Text fields
    o.plain_text,
    o.html_with_citations,

    CASE
        WHEN o.plain_text IS NULL OR LENGTH(TRIM(o.plain_text)) = 0 THEN false
        ELSE true
    END AS has_plain_text,

    CASE
        WHEN o.html_with_citations IS NULL OR LENGTH(TRIM(o.html_with_citations)) = 0 THEN false
        ELSE true
    END AS has_html_with_citations,

    LENGTH(o.plain_text) AS plain_text_length,
    LENGTH(o.html_with_citations) AS html_with_citations_length

FROM public.search_opinion o
JOIN public.search_opinioncluster oc
    ON o.cluster_id = oc.id
JOIN public.search_docket d
    ON oc.docket_id = d.id
JOIN ext.federal_appeal_courts c
    ON d.court_id = c.id;

ALTER TABLE ext.federal_appeal_opinions
ADD PRIMARY KEY (opinion_id);


-- ------------------------------------------------------------
-- 3. Indexes for fast analysis
-- ------------------------------------------------------------

CREATE INDEX idx_fao_cluster_id
    ON ext.federal_appeal_opinions(cluster_id);

CREATE INDEX idx_fao_docket_id
    ON ext.federal_appeal_opinions(docket_id);

CREATE INDEX idx_fao_court_id
    ON ext.federal_appeal_opinions(court_id);

CREATE INDEX idx_fao_date_filed
    ON ext.federal_appeal_opinions(date_filed);

CREATE INDEX idx_fao_year_filed
    ON ext.federal_appeal_opinions(year_filed);

CREATE INDEX idx_fao_author_id
    ON ext.federal_appeal_opinions(author_id);

CREATE INDEX idx_fao_opinion_type
    ON ext.federal_appeal_opinions(opinion_type);

CREATE INDEX idx_fao_precedential_status
    ON ext.federal_appeal_opinions(precedential_status);

CREATE INDEX idx_fao_has_plain_text
    ON ext.federal_appeal_opinions(has_plain_text);

CREATE INDEX idx_fao_has_html_with_citations
    ON ext.federal_appeal_opinions(has_html_with_citations);

CREATE INDEX idx_fao_cluster_nature_of_suit
    ON ext.federal_appeal_opinions(cluster_nature_of_suit);

CREATE INDEX idx_fao_docket_nature_of_suit
    ON ext.federal_appeal_opinions(docket_nature_of_suit);

CREATE INDEX idx_fao_docket_jurisdiction_type
    ON ext.federal_appeal_opinions(docket_jurisdiction_type);


-- ------------------------------------------------------------
-- 4. Create smaller metadata-only version without large text fields
-- ------------------------------------------------------------

CREATE TABLE ext.federal_appeal_opinion_meta AS
SELECT
    opinion_id,
    cluster_id,
    docket_id,
    court_id,
    court_short_name,
    court_full_name,
    date_filed,
    year_filed,
    case_name,
    case_name_full,
    precedential_status,
    citation_count,
    cluster_nature_of_suit,
    docket_number,
    docket_number_core,
    docket_nature_of_suit,
    docket_cause,
    docket_jurisdiction_type,
    author_id,
    author_str,
    opinion_type,
    per_curiam,
    page_count,
    has_plain_text,
    has_html_with_citations,
    plain_text_length,
    html_with_citations_length
FROM ext.federal_appeal_opinions;

ALTER TABLE ext.federal_appeal_opinion_meta
ADD PRIMARY KEY (opinion_id);

CREATE INDEX idx_fao_meta_cluster_id
    ON ext.federal_appeal_opinion_meta(cluster_id);

CREATE INDEX idx_fao_meta_docket_id
    ON ext.federal_appeal_opinion_meta(docket_id);

CREATE INDEX idx_fao_meta_court_id
    ON ext.federal_appeal_opinion_meta(court_id);

CREATE INDEX idx_fao_meta_date_filed
    ON ext.federal_appeal_opinion_meta(date_filed);

CREATE INDEX idx_fao_meta_year_filed
    ON ext.federal_appeal_opinion_meta(year_filed);

CREATE INDEX idx_fao_meta_author_id
    ON ext.federal_appeal_opinion_meta(author_id);

CREATE INDEX idx_fao_meta_opinion_type
    ON ext.federal_appeal_opinion_meta(opinion_type);

CREATE INDEX idx_fao_meta_precedential_status
    ON ext.federal_appeal_opinion_meta(precedential_status);

CREATE INDEX idx_fao_meta_has_plain_text
    ON ext.federal_appeal_opinion_meta(has_plain_text);

CREATE INDEX idx_fao_meta_has_html_with_citations
    ON ext.federal_appeal_opinion_meta(has_html_with_citations);

CREATE INDEX idx_fao_meta_cluster_nature_of_suit
    ON ext.federal_appeal_opinion_meta(cluster_nature_of_suit);

CREATE INDEX idx_fao_meta_docket_nature_of_suit
    ON ext.federal_appeal_opinion_meta(docket_nature_of_suit);

CREATE INDEX idx_fao_meta_docket_jurisdiction_type
    ON ext.federal_appeal_opinion_meta(docket_jurisdiction_type);

COMMIT;