-- ============================================================
-- 08_author_party_timeaware.sql
--
-- Purpose:
--   A corrected party variable for the deposit. Two changes against
--   the legacy merged party table:
--
--   1. SEPARATE CONCEPTS. The party of the appointing president and the
--      judge's own recorded affiliation are different measures and are
--      kept in different columns. A merged convenience column is still
--      provided, but it is explicitly derived and labelled.
--
--   2. POINT IN TIME. The recorded affiliation is resolved as of the
--      FILING DATE of the opinion, not as the most recently recorded
--      affiliation.
--
--   Why "greatest date_start <= filing date" is the right rule here:
--   of 8,486 affiliation rows only 64 carry a date_end, while 4,117
--   carry a date_start. The records are therefore open intervals that
--   supersede one another, not closed spells, so the affiliation in
--   force is the most recent one that had already begun.
--
--   Scope of the correction: 1,825 of the matched judges have a single
--   affiliation and are unaffected. 112 have two or more; those are the
--   judges whose party could change with the filing date.
--
-- Output:
--   ext.author_party_timeaware   (new table; nothing existing is altered)
--
-- Prerequisites:
--   01_unique_person_attribution.sql
--   04_author_party_resolved.sql   (appointing-president party is read
--                                   from its rebuilt release table)
-- ============================================================

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.author_party_timeaware;

CREATE TABLE ext.author_party_timeaware AS
WITH opinion_dates AS (
    SELECT r.opinion_id, r.court_id, r.year_filed,
           m.date_filed,
           r.judge_id, r.cl_person_id, r.fjc_nid, r.id_registry
    FROM ext.author_person_resolved r
    JOIN ext.federal_appeal_opinion_meta m USING (opinion_id)
),

-- How many affiliations does each person have at all? A single record
-- needs no temporal reasoning and is reported as such.
aff_counts AS (
    SELECT person_id, count(*) AS n_affiliations,
           count(date_start) AS n_dated
    FROM public.people_db_politicalaffiliation
    GROUP BY 1
),

-- The affiliation in force on the filing date: the latest one that had
-- already started and has not ended before that date.
aff_at_filing AS (
    SELECT DISTINCT ON (d.opinion_id)
        d.opinion_id,
        pa.political_party,
        pa.date_start,
        pa.date_end
    FROM opinion_dates d
    JOIN public.people_db_politicalaffiliation pa
      ON pa.person_id = d.cl_person_id
     AND pa.date_start IS NOT NULL
     AND d.date_filed IS NOT NULL
     AND pa.date_start <= d.date_filed
     AND (pa.date_end IS NULL OR pa.date_end >= d.date_filed)
    ORDER BY d.opinion_id, pa.date_start DESC, pa.id DESC
),

-- The previous behaviour, kept for comparison and for anyone
-- reproducing earlier results.
aff_latest AS (
    SELECT DISTINCT ON (person_id) person_id, political_party
    FROM public.people_db_politicalaffiliation
    ORDER BY person_id, date_start DESC NULLS LAST, id DESC
),

-- Single undated affiliation: usable, but not placed in time.
aff_single AS (
    SELECT pa.person_id, pa.political_party
    FROM public.people_db_politicalaffiliation pa
    JOIN aff_counts c ON c.person_id = pa.person_id AND c.n_affiliations = 1
)

SELECT
    d.opinion_id,
    d.court_id,
    d.date_filed,
    d.year_filed,
    d.judge_id,
    d.id_registry,
    d.cl_person_id,
    d.fjc_nid,

    -- ---- Measure 1: party of the appointing president -------------
    p.fjc_appointing_party            AS appointing_president_party,
    p.fjc_appointment_match_quality   AS appointing_match_quality,

    -- ---- Measure 2: the judge's own recorded affiliation ----------
    COALESCE(f.political_party, s.political_party) AS registered_party_code,
    CASE COALESCE(f.political_party, s.political_party)
        WHEN 'd' THEN 'Democratic'      WHEN 'r' THEN 'Republican'
        WHEN 'i' THEN 'Independent'     WHEN 'g' THEN 'Green'
        WHEN 'l' THEN 'Libertarian'     WHEN 'f' THEN 'Federalist'
        WHEN 'w' THEN 'Whig'            WHEN 'j' THEN 'Jeffersonian Republican'
        WHEN 'u' THEN 'National Union'  WHEN 'z' THEN 'Reform Party'
        ELSE NULL
    END AS registered_party,

    CASE
        WHEN f.political_party IS NOT NULL THEN 'in_force_at_filing'
        WHEN s.political_party IS NOT NULL THEN 'single_undated_record'
        WHEN d.cl_person_id IS NULL        THEN 'no_courtlistener_person'
        WHEN c.person_id IS NULL           THEN 'no_affiliation_recorded'
        WHEN d.date_filed IS NULL          THEN 'no_filing_date'
        ELSE 'filing_outside_recorded_periods'
    END AS registered_party_resolution,

    c.n_affiliations   AS registered_n_records,
    f.date_start       AS registered_period_start,
    f.date_end         AS registered_period_end,

    -- Previous behaviour: most recently recorded affiliation, ignoring
    -- the filing date. Retained only so the two can be compared.
    l.political_party  AS registered_party_code_latest_record,

    -- ---- Derived convenience column -------------------------------
    -- NOT a measurement in its own right. It prefers the appointing
    -- president's party, the standard measure in judicial-politics
    -- research, and falls back to the judge's own affiliation. Analyses
    -- should state which of the two they mean and use that column.
    COALESCE(
        NULLIF(CASE WHEN p.fjc_appointing_party LIKE 'None%' THEN NULL
                    ELSE p.fjc_appointing_party END, ''),
        CASE COALESCE(f.political_party, s.political_party)
            WHEN 'd' THEN 'Democratic'      WHEN 'r' THEN 'Republican'
            WHEN 'i' THEN 'Independent'     WHEN 'g' THEN 'Green'
            WHEN 'l' THEN 'Libertarian'     WHEN 'f' THEN 'Federalist'
            WHEN 'w' THEN 'Whig'            WHEN 'j' THEN 'Jeffersonian Republican'
            WHEN 'u' THEN 'National Union'  WHEN 'z' THEN 'Reform Party'
            ELSE NULL
        END
    ) AS party_convenience,

    CASE
        WHEN p.fjc_appointing_party IS NOT NULL
         AND p.fjc_appointing_party NOT LIKE 'None%'         THEN 'appointing_president'
        WHEN COALESCE(f.political_party, s.political_party) IS NOT NULL
                                                             THEN 'registered_affiliation'
        ELSE NULL
    END AS party_convenience_source

FROM opinion_dates d
LEFT JOIN ext.author_party_resolved_rebuilt p ON p.opinion_id = d.opinion_id
LEFT JOIN aff_at_filing            f ON f.opinion_id  = d.opinion_id
LEFT JOIN aff_single               s ON s.person_id   = d.cl_person_id
LEFT JOIN aff_latest               l ON l.person_id   = d.cl_person_id
LEFT JOIN aff_counts               c ON c.person_id   = d.cl_person_id;

ALTER TABLE ext.author_party_timeaware ADD PRIMARY KEY (opinion_id);
CREATE INDEX idx_apt_person     ON ext.author_party_timeaware(cl_person_id);
CREATE INDEX idx_apt_resolution ON ext.author_party_timeaware(registered_party_resolution);

COMMENT ON TABLE ext.author_party_timeaware IS
'Party of the appointing president and the judge''s own recorded affiliation as of the opinion filing date, kept as separate measures. Built from the current publication attribution table.';

COMMIT;

ANALYZE ext.author_party_timeaware;
