-- ============================================================
-- 04_author_party_resolved.sql
--
-- Purpose:
--   Reconstructed DDL for ext.author_party_resolved. The table existed
--   in the database but its creation script was lost; this script was
--   rebuilt from the table's contents and from the description in
--   old/old_4/36_gender_axis_by_author_and_time_11.ipynb, then verified
--   to reproduce the original table exactly (see 05_verify_*.sql).
--
--   Per opinion, it resolves the author's political party two ways:
--     1. fjc_appointer  -- party of the appointing president, the
--        standard measure in judicial-politics research
--     2. cl_registered  -- CourtListener's recorded affiliation, used
--        as a fallback
--   The FJC measure takes priority where both exist.
--
-- Coverage caveat (state it, do not paper over it):
--   The preferred measure is the scarce one. Of the attributions with a
--   party, only about 6.5 % come from fjc_appointer; the rest are
--   CourtListener's recorded affiliation. The party variable in this
--   table is therefore predominantly registered affiliation, not
--   appointing party.
--
-- Known weakness of cl_political_party:
--   CourtListener can record several affiliations per judge with
--   validity periods. This table takes the MOST RECENTLY RECORDED one
--   (latest date_start), not the one in force on the filing date. For
--   112 judges and 40,639 opinions those differ -- e.g. a judge whose
--   record runs Republican 1954-1964 and Democratic from 1964 is
--   labelled Democratic for opinions written in 1959. Analyses that
--   depend on party at the time of writing should re-derive the value
--   with a period join instead of reusing party_final.
--
-- Prerequisite: 01_unique_person_attribution.sql
-- ============================================================

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.author_party_resolved_rebuilt;

CREATE TABLE ext.author_party_resolved_rebuilt AS
WITH base AS (
    -- One row per gender-resolved opinion, with the judge identifier
    -- recovered by routing back through the channel that resolved gender.
    SELECT
        r.opinion_id,
        r.court_id,
        r.year_filed,
        r.gender,
        r.channel,
        r.judge_id,
        CASE WHEN r.judge_id ~ '^[0-9]+$' THEN r.judge_id::int END AS judge_id_num,
        r.cl_person_id AS matched_person_id
    FROM ext.author_person_resolved r
),

-- The FJC side is reachable two ways: the judge id IS an FJC nid, or it
-- is a CourtListener person whose people_db_person.fjc_id points into the
-- FJC biography table.
nid_bridge AS (
    SELECT
        b.*,
        COALESCE(
            (SELECT bio.nid FROM ext.fjc_judge_bio bio WHERE bio.nid = b.judge_id_num),
            (SELECT p.fjc_id FROM public.people_db_person p
              WHERE p.id = b.matched_person_id
                AND p.fjc_id IS NOT NULL
                AND EXISTS (SELECT 1 FROM ext.fjc_judge_bio bio2 WHERE bio2.nid = p.fjc_id))
        ) AS fjc_nid
    FROM base b
),

-- Appointing party, preferring a service record for the deciding court
-- whose period covers the filing year.
fjc_party AS (
    SELECT DISTINCT ON (n.opinion_id)
        n.opinion_id,
        jc.party_of_appointing_president AS fjc_appointing_party,
        CASE
            WHEN m.court_id IS NOT NULL AND n.year_filed IS NOT NULL
             AND n.year_filed >= EXTRACT(YEAR FROM jc.commission_date)
             AND (jc.termination_date IS NULL
                  OR n.year_filed <= EXTRACT(YEAR FROM jc.termination_date))
                THEN 'court_and_period'
            WHEN m.court_id IS NOT NULL
                THEN 'court_only'
            ELSE 'any_court'
        END AS fjc_appointment_match_quality
    FROM nid_bridge n
    JOIN ext.fjc_judge_court jc ON jc.nid = n.fjc_nid
    LEFT JOIN ext.fjc_court_name_map m
           ON m.fjc_court_name = jc.court_name
          AND m.court_id = n.court_id
    WHERE n.fjc_nid IS NOT NULL
    ORDER BY n.opinion_id,
             CASE
                 WHEN m.court_id IS NOT NULL AND n.year_filed IS NOT NULL
                  AND n.year_filed >= EXTRACT(YEAR FROM jc.commission_date)
                  AND (jc.termination_date IS NULL
                       OR n.year_filed <= EXTRACT(YEAR FROM jc.termination_date))
                     THEN 1
                 WHEN m.court_id IS NOT NULL THEN 2
                 ELSE 3
             END,
             jc.commission_date DESC NULLS LAST,
             jc.id
),

-- CourtListener affiliation: the most recently RECORDED one. See the
-- header -- this is deliberately not a period join, because that is what
-- the original table did.
cl_party AS (
    SELECT DISTINCT ON (person_id) person_id, political_party
    FROM public.people_db_politicalaffiliation
    ORDER BY person_id, date_start DESC NULLS LAST, id DESC
)

SELECT
    n.opinion_id,
    n.court_id,
    n.year_filed,
    n.gender,
    n.channel,
    n.judge_id,
    n.judge_id_num,
    n.matched_person_id,
    c.political_party            AS cl_political_party,
    f.fjc_appointing_party,
    f.fjc_appointment_match_quality,

    -- Priority: appointing party, then recorded affiliation.
    -- 'None (reassignment)' is not a party and stays unresolved.
    CASE
        WHEN f.fjc_appointing_party IS NOT NULL
         AND f.fjc_appointing_party NOT LIKE 'None%'
            THEN f.fjc_appointing_party
        ELSE CASE c.political_party
            WHEN 'd' THEN 'Democratic'
            WHEN 'r' THEN 'Republican'
            WHEN 'i' THEN 'Independent'
            WHEN 'g' THEN 'Green'
            WHEN 'l' THEN 'Libertarian'
            WHEN 'f' THEN 'Federalist'
            WHEN 'w' THEN 'Whig'
            WHEN 'j' THEN 'Jeffersonian Republican'
            WHEN 'u' THEN 'National Union'
            WHEN 'z' THEN 'Reform Party'
            ELSE NULL
        END
    END AS party_final,

    CASE
        WHEN f.fjc_appointing_party IS NOT NULL
         AND f.fjc_appointing_party NOT LIKE 'None%'
            THEN 'fjc_appointer'
        WHEN c.political_party IS NOT NULL
            THEN 'cl_registered'
        ELSE NULL
    END AS party_source

FROM nid_bridge n
LEFT JOIN fjc_party f ON f.opinion_id = n.opinion_id
LEFT JOIN cl_party  c ON c.person_id  = n.matched_person_id;

ALTER TABLE ext.author_party_resolved_rebuilt ADD PRIMARY KEY (opinion_id);

CREATE INDEX idx_apr_reb_party  ON ext.author_party_resolved_rebuilt(party_final);
CREATE INDEX idx_apr_reb_judge  ON ext.author_party_resolved_rebuilt(judge_id);

COMMENT ON TABLE ext.author_party_resolved_rebuilt IS
'Reconstruction of ext.author_party_resolved from a lost build script. Party of the appointing president (preferred) or CourtListener recorded affiliation (fallback) per attributed opinion.';

COMMIT;

ANALYZE ext.author_party_resolved_rebuilt;
