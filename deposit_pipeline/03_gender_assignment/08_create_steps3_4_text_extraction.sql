-- ============================================================
-- 08_create_steps3_4_text_extraction.sql
--
-- Purpose:
--   Extract author names from text fields and match against the
--   unified judge pool to resolve gender for opinions still
--   unresolved after Steps 1+2 (Steps 3 and 4).
--
--   Step 3: XML <author> tag extraction from xml_harvard.
--   Step 4: HTML body text extraction from html_with_citations
--           (restricted to published, non-per curiam opinions
--           filed from 1960 onwards).
--
--   XML extraction takes priority over HTML extraction.
--   Both branches are preserved as diagnostic columns (xml_*,
--   html_*) in the output table.
--
--   The publication release reconstructs the historical five-line panel
--   guard from the original layout convention: only a literal "Before:"
--   line opens a panel-header block.  This rule reproduces every resolved
--   thesis attribution and corrects one historical false negative
--   (opinion 2966699), whose valid author line follows a rejected panel
--   candidate.  No per-opinion compatibility overrides are applied.
--
-- Judge pool (same as Steps 1+2):
--   (1) CourtListener people_db_person + people_db_position
--   (2) FJC judge bio + FJC court data
--   (3) ext.supplemental_judges
--   (4) District-court judges for any-court by-designation matches
--
-- HTML layout types:
--   harvard_structured  class="indent" paragraphs (Harvard CAP)
--   xml_inline          starts with <?xml declaration
--   pre_inline          starts with <pre class="inline"> tag
--   plain_html          all other HTML
--
-- HTML extraction patterns (H1--H8, see Appendix):
--   Strong: H1 Opinion by Judge NAME
--           H2 Opinion by NAME, Circuit/District Judge
--           H3 Judge NAME delivered the opinion
--   Weak:   H4 NAME, Circuit/District Judge (plain_html, xml_inline)
--           H5 NAME, Circuit Judge only (pre_inline)
--           H6 NAME, Chief/Senior Judge (plain_html, xml_inline)
--           H7 Harvard: first indent after OPINION heading
--           H8 Harvard: first indent with judicial title
--
-- Output:
--   ext.author_gender_from_text_extraction
--       One row per qualifying unresolved opinion.
--
-- Prerequisites:
--   06_create_steps1_2_combined.sql
--   01_create_fjc_judge_tables.sql (02_judge_reference)
--   03_create_fjc_court_name_map.sql (02_judge_reference)
--   04_create_supplemental_judges.sql (02_judge_reference)
-- ============================================================

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.author_gender_from_text_extraction;

CREATE TABLE ext.author_gender_from_text_extraction AS
WITH

-- ===========================================================
-- 0. Base: qualifying unresolved opinions with text sources
-- ===========================================================
base AS (
    SELECT
        g.opinion_id,
        g.cluster_id,
        g.docket_id,
        g.court_id,
        g.court_short_name,
        g.date_filed,
        g.year_filed,
        g.case_name,
        o.type                  AS opinion_type,
        oc.precedential_status,
        o.per_curiam,
        g.author_id,
        g.author_str,
        o.xml_harvard,
        o.html_with_citations
    FROM ext.author_gender_final g
    JOIN public.search_opinion o
        ON o.id = g.opinion_id
    JOIN public.search_opinioncluster oc
        ON oc.id = g.cluster_id
    WHERE g.gender_resolved = FALSE
      AND oc.precedential_status = 'Published'
      AND COALESCE(o.per_curiam, FALSE) = FALSE
      AND (
          (o.xml_harvard IS NOT NULL AND o.xml_harvard ILIKE '%<author%')
          OR
          (g.year_filed >= 1960
           AND o.html_with_citations IS NOT NULL
           AND BTRIM(o.html_with_citations) <> '')
      )
),

-- ===========================================================
-- 1. Judge pool: CourtListener (primary), FJC (fallback),
--    Supplemental (manual additions)
-- ===========================================================
all_judges AS (
    -- Primary: CourtListener people_db
    SELECT
        p.id::text                                                                      AS judge_id,
        LOWER(REGEXP_REPLACE(COALESCE(p.name_last, ''), '[^[:alpha:]]', '', 'g'))       AS last_name_norm,
        LOWER(REGEXP_REPLACE(
            CONCAT_WS(' ',
                NULLIF(BTRIM(COALESCE(p.name_first,  '')), ''),
                NULLIF(BTRIM(COALESCE(p.name_middle, '')), ''),
                NULLIF(BTRIM(COALESCE(p.name_last,   '')), '')
            ), '[^[:alpha:]]', '', 'g'))                                                AS full_name_norm,
        BTRIM(CONCAT_WS(' ',
            NULLIF(BTRIM(COALESCE(p.name_first, '')), ''),
            NULLIF(BTRIM(COALESCE(p.name_last,  '')), '')))                             AS display_name,
        LOWER(LEFT(NULLIF(BTRIM(COALESCE(p.name_first,  '')), ''), 1))                 AS first_initial,
        LOWER(LEFT(NULLIF(BTRIM(COALESCE(p.name_middle, '')), ''), 1))                 AS mid_initial,
        p.gender,
        pos.court_id,
        MIN(pos.date_start)       AS start_date,
        MAX(pos.date_termination) AS end_date
    FROM people_db_person p
    JOIN people_db_position pos ON pos.person_id = p.id
    WHERE p.gender IN ('m', 'f')
      AND pos.court_id IN ('ca1','ca2','ca3','ca4','ca5','ca6',
                           'ca7','ca8','ca9','ca10','ca11','cafc','cadc')
      AND pos.position_type IN ('jud', 'ret-senior-jud', 'c-jus')
    GROUP BY p.id, p.name_first, p.name_middle, p.name_last, p.gender, pos.court_id

    UNION ALL

    -- Fallback: FJC (not already covered by CL at the same court)
    SELECT
        b.nid::text                                                                     AS judge_id,
        LOWER(REGEXP_REPLACE(COALESCE(b.last_name, ''), '[^[:alpha:]]', '', 'g'))       AS last_name_norm,
        LOWER(REGEXP_REPLACE(
            CONCAT_WS(' ', b.first_name, b.middle_name, b.last_name),
            '[^[:alpha:]]', '', 'g'))                                                   AS full_name_norm,
        BTRIM(CONCAT_WS(' ', b.first_name, b.last_name))                               AS display_name,
        LOWER(SUBSTRING(COALESCE(b.first_name,  '') FROM 1 FOR 1))                     AS first_initial,
        LOWER(SUBSTRING(COALESCE(b.middle_name, '') FROM 1 FOR 1))                     AS mid_initial,
        b.gender,
        cm.court_id,
        jc.commission_date  AS start_date,
        jc.termination_date AS end_date
    FROM ext.fjc_judge_bio b
    JOIN ext.fjc_judge_court   jc ON jc.nid          = b.nid
    JOIN ext.fjc_court_name_map cm ON cm.fjc_court_name = jc.court_name
    WHERE b.gender IS NOT NULL
      AND BTRIM(b.gender) <> ''
      AND b.last_name IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM people_db_person p
          JOIN people_db_position pos2 ON pos2.person_id = p.id
          WHERE p.fjc_id = b.jid
            AND p.gender IN ('m', 'f')
            AND pos2.court_id = cm.court_id
            AND pos2.position_type IN ('jud', 'ret-senior-jud', 'c-jus')
      )

    UNION ALL

    -- Supplemental: manually curated (name-change cases, by-designation)
    SELECT
        'sup_' || s.sup_id::text                                                        AS judge_id,
        LOWER(REGEXP_REPLACE(COALESCE(s.name_last, ''), '[^[:alpha:]]', '', 'g'))       AS last_name_norm,
        LOWER(REGEXP_REPLACE(
            CONCAT_WS(' ',
                NULLIF(BTRIM(COALESCE(s.name_first,  '')), ''),
                NULLIF(BTRIM(COALESCE(s.name_middle, '')), ''),
                NULLIF(BTRIM(COALESCE(s.name_last,   '')), '')),
            '[^[:alpha:]]', '', 'g'))                                                   AS full_name_norm,
        BTRIM(CONCAT_WS(' ',
            NULLIF(BTRIM(COALESCE(s.name_first, '')), ''),
            NULLIF(BTRIM(COALESCE(s.name_last,  '')), '')))                             AS display_name,
        LOWER(LEFT(NULLIF(BTRIM(COALESCE(s.name_first,  '')), ''), 1))                 AS first_initial,
        LOWER(LEFT(NULLIF(BTRIM(COALESCE(s.name_middle, '')), ''), 1))                 AS mid_initial,
        s.gender,
        s.court_id,
        s.start_date,
        s.end_date
    FROM ext.supplemental_judges s

    UNION ALL

    -- District court judges (by-designation authors on circuit court opinions)
    -- Their court_id will not match any circuit court_id, so they only contribute
    -- via any-court tiers (7/8) – prevents false positives on same-court tiers.
    -- Not already covered by the CL circuit pool above.
    SELECT
        p.id::text                                                                      AS judge_id,
        LOWER(REGEXP_REPLACE(COALESCE(p.name_last, ''), '[^[:alpha:]]', '', 'g'))       AS last_name_norm,
        LOWER(REGEXP_REPLACE(
            CONCAT_WS(' ',
                NULLIF(BTRIM(COALESCE(p.name_first,  '')), ''),
                NULLIF(BTRIM(COALESCE(p.name_middle, '')), ''),
                NULLIF(BTRIM(COALESCE(p.name_last,   '')), '')
            ), '[^[:alpha:]]', '', 'g'))                                                AS full_name_norm,
        BTRIM(CONCAT_WS(' ',
            NULLIF(BTRIM(COALESCE(p.name_first, '')), ''),
            NULLIF(BTRIM(COALESCE(p.name_last,  '')), '')))                             AS display_name,
        LOWER(LEFT(NULLIF(BTRIM(COALESCE(p.name_first,  '')), ''), 1))                 AS first_initial,
        LOWER(LEFT(NULLIF(BTRIM(COALESCE(p.name_middle, '')), ''), 1))                 AS mid_initial,
        p.gender,
        pos.court_id,
        MIN(pos.date_start)       AS start_date,
        MAX(pos.date_termination) AS end_date
    FROM people_db_person p
    JOIN people_db_position pos ON pos.person_id = p.id
    WHERE p.gender IN ('m', 'f')
      AND pos.position_type IN ('jud', 'ret-senior-jud', 'c-jus')
      AND pos.court_id NOT IN ('ca1','ca2','ca3','ca4','ca5','ca6',
                               'ca7','ca8','ca9','ca10','ca11','cafc','cadc')
    GROUP BY p.id, p.name_first, p.name_middle, p.name_last, p.gender, pos.court_id
),

-- ===========================================================
-- 2. XML branch  –  extract from xml_harvard (<author> tag)
-- ===========================================================

-- 2a. Extract raw <author> tag content
xml_raw AS (
    SELECT
        opinion_id,
        SUBSTRING(xml_harvard FROM '<author[^>]*>(.*?)</author>') AS raw_author_tag
    FROM base
    WHERE xml_harvard IS NOT NULL
      AND xml_harvard ILIKE '%<author%'
),

-- 2b. Clean the raw tag (strip sub-tags, entities, leading noise)
xml_cleaned AS (
    SELECT
        opinion_id,
        raw_author_tag,
        NULLIF(
            BTRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    REGEXP_REPLACE(
                                        REGEXP_REPLACE(
                                            REGEXP_REPLACE(
                                                COALESCE(raw_author_tag, ''),
                                                '<[^>]+>', ' ', 'g'),
                                            '&amp;', '&', 'g'),
                                        '&lt;', '<', 'g'),
                                    '&gt;', '>', 'g'),
                                '&#39;', '''', 'g'),
                            '&quot;', '"', 'g'),
                        '\s+', ' ', 'g'),
                    '^[*[:space:]0-9]+', '', 'g')
            ),
            ''
        ) AS clean_author_tag
    FROM xml_raw
    WHERE raw_author_tag IS NOT NULL
),

-- 2c. Extract author name from cleaned tag; filter procedural entries
xml_name_extracted AS (
    SELECT
        opinion_id,
        raw_author_tag,
        clean_author_tag,
        CASE
            -- Exclude collective / procedural tags
            WHEN clean_author_tag ~* '(^|[^[:alpha:]])per[[:space:].]+curiam([^[:alpha:]]|$)'
              OR clean_author_tag ~* '(^|[^[:alpha:]])by[[:space:]]+the[[:space:]]+court([^[:alpha:]]|$)'
              OR clean_author_tag ~* '(^|[^[:alpha:]])by[[:space:]]+the[[:space:]]+panel([^[:alpha:]]|$)'
              OR clean_author_tag ~* '(^|[^[:alpha:]])memorandum([^[:alpha:]]|$)'
              OR clean_author_tag ~* '^[[:space:]]*order\.?[[:space:]]*$'
              OR clean_author_tag ~* '^[[:space:]]*summary[[:space:]]+order\.?[[:space:]]*$'
              OR clean_author_tag ~* 'dissenting[[:space:]]+opinion[[:space:]]+filed[[:space:]]+by'
              OR clean_author_tag ~* 'concurring[[:space:]]+opinion[[:space:]]+filed[[:space:]]+by'
              OR clean_author_tag ~* 'opinion[[:space:]]+for[[:space:]]+the[[:space:]]+court[[:space:]]+filed[[:space:]]+by'
              OR clean_author_tag ~* 'opinion[[:space:]]+filed[[:space:]]+by'
                THEN NULL

            -- "NAME, [Jr.,] [Chief/Senior] [Circuit/District] Judge" pattern
            WHEN clean_author_tag ~* '^[[:alpha:]][[:alpha:].''ÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÑÇáéíóúàèìòùäëïöüñç\- ]+(,[[:space:]]*(jr|sr|ii|iii|iv|v)\.?)?,[[:space:]]*(chief[[:space:]]+district[[:space:]]+judge|chief[[:space:]]+judge|senior[[:space:]]+district[[:space:]]+judge|senior[[:space:]]+circuit[[:space:]]+judge|circuit[[:space:]]+judge|district[[:space:]]+judge|associate[[:space:]]+justice|chief[[:space:]]+justice|justice|judge)'
                THEN BTRIM(
                    SUBSTRING(
                        clean_author_tag FROM '^([^,]+(?:,[[:space:]]*(?:[Jj][Rr]|[Ss][Rr]|II|III|IV|V)\.?)?),[[:space:]]*(?:[Cc]hief[[:space:]]+[Dd]istrict[[:space:]]+[Jj]udge|[Cc]hief[[:space:]]+[Jj]udge|[Ss]enior[[:space:]]+[Dd]istrict[[:space:]]+[Jj]udge|[Ss]enior[[:space:]]+[Cc]ircuit[[:space:]]+[Jj]udge|[Cc]ircuit[[:space:]]+[Jj]udge|[Dd]istrict[[:space:]]+[Jj]udge|[Aa]ssociate[[:space:]]+[Jj]ustice|[Cc]hief[[:space:]]+[Jj]ustice|[Jj]ustice|[Jj]udge)'
                    )
                )

            -- "NAME [Chief/Senior] [Circuit/District] Judge" (space before title)
            WHEN clean_author_tag ~* '^[[:alpha:]][[:alpha:].''ÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÑÇáéíóúàèìòùäëïöüñç\- ]+[[:space:]]+(chief[[:space:]]+district[[:space:]]+judge|chief[[:space:]]+judge|senior[[:space:]]+district[[:space:]]+judge|senior[[:space:]]+circuit[[:space:]]+judge|circuit[[:space:]]+judge|district[[:space:]]+judge|associate[[:space:]]+justice|chief[[:space:]]+justice|justice|judge)'
                THEN BTRIM(
                    SUBSTRING(
                        clean_author_tag FROM '^(.+?)[[:space:]]+(?:[Cc]hief[[:space:]]+[Dd]istrict[[:space:]]+[Jj]udge|[Cc]hief[[:space:]]+[Jj]udge|[Ss]enior[[:space:]]+[Dd]istrict[[:space:]]+[Jj]udge|[Ss]enior[[:space:]]+[Cc]ircuit[[:space:]]+[Jj]udge|[Cc]ircuit[[:space:]]+[Jj]udge|[Dd]istrict[[:space:]]+[Jj]udge|[Aa]ssociate[[:space:]]+[Jj]ustice|[Cc]hief[[:space:]]+[Jj]ustice|[Jj]ustice|[Jj]udge)'
                    )
                )

            ELSE NULL
        END AS extracted_author_name
    FROM xml_cleaned
),

-- 2d. Normalise extracted XML name
xml_normed AS (
    SELECT
        b.opinion_id,
        b.cluster_id,
        b.docket_id,
        b.court_id,
        b.court_short_name,
        b.date_filed,
        b.year_filed,
        b.case_name,
        b.opinion_type,
        b.precedential_status,
        b.per_curiam,
        x.raw_author_tag,
        x.clean_author_tag,
        x.extracted_author_name,

        -- Suffix stripped (Jr./Sr./II/III/IV/V)
        NULLIF(
            BTRIM(REGEXP_REPLACE(
                x.extracted_author_name,
                ',?[[:space:]]+(Jr|Sr|II|III|IV|V)\.?$', '', 'i'
            )),
            ''
        ) AS xml_name_without_suffix,

        -- Full-name norm (letters only, lowercase)
        LOWER(REGEXP_REPLACE(
            COALESCE(
                NULLIF(BTRIM(REGEXP_REPLACE(
                    x.extracted_author_name,
                    ',?[[:space:]]+(Jr|Sr|II|III|IV|V)\.?$', '', 'i'
                )), ''),
                x.extracted_author_name
            ),
            '[^[:alpha:]]', '', 'g'
        )) AS xml_full_name_norm,

        -- Last-name norm: last word of suffix-stripped name
        LOWER(REGEXP_REPLACE(
            REPLACE(REPLACE(
                REGEXP_REPLACE(
                    SUBSTRING(
                        NULLIF(BTRIM(REGEXP_REPLACE(
                            x.extracted_author_name,
                            ',?[[:space:]]+(Jr|Sr|II|III|IV|V)\.?$', '', 'i'
                        )), '')
                        FROM '([^[:space:]]+)$'
                    ),
                    '[^[:alpha:]''\-]', '', 'g'),
                '''', ''), '-', ''),
            '-', '', 'g'
        )) AS xml_last_name_norm,

        -- First initial
        LOWER(SUBSTRING(
            REGEXP_REPLACE(COALESCE(x.extracted_author_name, ''), '^[^[:alpha:]]+', '')
            FROM 1 FOR 1
        )) AS xml_first_initial,

        -- Middle initial (compact D.W. or D W forms)
        CASE
            WHEN COALESCE(x.extracted_author_name, '') ~* '^[[:alpha:]][.][[:alpha:]][.][[:space:]]+'
                THEN LOWER(SUBSTRING(
                    COALESCE(x.extracted_author_name, '')
                    FROM '^[[:alpha:]][.]([[:alpha:]])[.][[:space:]]+'
                ))
            WHEN COALESCE(x.extracted_author_name, '') ~* '^[[:alpha:]][.]?[[:space:]]*[[:alpha:]][.]?[[:space:]]+'
                THEN LOWER(SUBSTRING(
                    COALESCE(x.extracted_author_name, '')
                    FROM '^[[:alpha:]][.]?[[:space:]]*([[:alpha:]])[.]?[[:space:]]+'
                ))
            ELSE NULL
        END AS xml_middle_initial,

        -- Is initial-form name? (e.g. D.W. NELSON, B. FLETCHER)
        CASE
            WHEN COALESCE(x.extracted_author_name, '') ~* '^[[:alpha:]][.]?[[:space:]]*[[:alpha:]]?[.]?[[:space:]]+[[:alpha:]''ÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÑÇáéíóúàèìòùäëïöüñç-]+$'
                THEN TRUE
            ELSE FALSE
        END AS xml_is_initial_name,

        cm.fjc_court_name AS xml_fjc_court_name

    FROM base b
    JOIN xml_name_extracted x ON x.opinion_id = b.opinion_id
    LEFT JOIN ext.fjc_court_name_map cm ON cm.court_id = b.court_id
    WHERE x.extracted_author_name IS NOT NULL
      AND x.extracted_author_name !~* '(^|[[:space:]])(Circuit|District|Judge|Justice|Chief|Senior|Associate|U\.S\.D\.J\.)([[:space:]]|$)'
      AND x.extracted_author_name !~* 'opinion[[:space:]]+for[[:space:]]+the[[:space:]]+court'
      AND x.extracted_author_name !~* 'opinion[[:space:]]+filed[[:space:]]+by'
      AND x.extracted_author_name !~* 'dissenting[[:space:]]+opinion'
      AND x.extracted_author_name !~* 'concurring[[:space:]]+opinion'
      AND x.extracted_author_name !~* 'by[[:space:]]+the[[:space:]]+court'
      AND x.extracted_author_name !~* 'by[[:space:]]+the[[:space:]]+panel'
      AND LENGTH(x.extracted_author_name) >= 3
      AND LENGTH(x.extracted_author_name) <= 80
      AND x.extracted_author_name ~ '[[:alpha:]]'
),

-- 2e. Match XML names against judge pool
xml_candidates AS (
    SELECT
        x.opinion_id,
        f.judge_id,
        f.gender,
        f.full_name_norm,
        f.last_name_norm,
        f.first_initial,
        f.mid_initial,
        f.display_name,
        CASE
            WHEN f.full_name_norm = x.xml_full_name_norm
             AND f.court_id = x.court_id
                THEN 'exact_full_name_same_court'

            WHEN x.xml_is_initial_name = TRUE
             AND f.last_name_norm = x.xml_last_name_norm
             AND f.first_initial  = x.xml_first_initial
             AND (x.xml_middle_initial IS NULL OR x.xml_middle_initial = ''
                  OR f.mid_initial = x.xml_middle_initial)
             AND f.court_id = x.court_id
                THEN 'initials_last_name_same_court'

            WHEN f.full_name_norm = x.xml_full_name_norm
                THEN 'exact_full_name_any_court'

            WHEN x.xml_is_initial_name = TRUE
             AND f.last_name_norm = x.xml_last_name_norm
             AND f.first_initial  = x.xml_first_initial
             AND (x.xml_middle_initial IS NULL OR x.xml_middle_initial = ''
                  OR f.mid_initial = x.xml_middle_initial)
                THEN 'initials_last_name_any_court'

            WHEN f.last_name_norm = x.xml_last_name_norm
             AND f.court_id = x.court_id
             AND (f.start_date IS NULL
                  OR EXTRACT(YEAR FROM f.start_date) <= x.year_filed)
             AND (f.end_date IS NULL
                  OR EXTRACT(YEAR FROM f.end_date) >= x.year_filed)
             AND (x.xml_full_name_norm = x.xml_last_name_norm
                  OR x.xml_first_initial IS NULL OR x.xml_first_initial = ''
                  OR f.first_initial = x.xml_first_initial)
                THEN 'last_name_same_court_active_period'

            WHEN f.last_name_norm = x.xml_last_name_norm
             AND f.court_id = x.court_id
             AND (x.xml_full_name_norm = x.xml_last_name_norm
                  OR x.xml_first_initial IS NULL OR x.xml_first_initial = ''
                  OR f.first_initial = x.xml_first_initial)
                THEN 'last_name_same_court'

            ELSE NULL
        END AS match_type
    FROM xml_normed x
    JOIN all_judges f
      ON (   f.full_name_norm  = x.xml_full_name_norm
          OR f.last_name_norm  = x.xml_last_name_norm)
),

xml_ranked AS (
    SELECT *,
        CASE match_type
            WHEN 'exact_full_name_same_court'         THEN 1
            WHEN 'initials_last_name_same_court'      THEN 2
            WHEN 'exact_full_name_any_court'          THEN 3
            WHEN 'initials_last_name_any_court'       THEN 4
            WHEN 'last_name_same_court_active_period' THEN 5
            WHEN 'last_name_same_court'               THEN 6
            ELSE 99
        END AS match_priority
    FROM xml_candidates
    WHERE match_type IS NOT NULL
),

xml_best_priority AS (
    SELECT opinion_id, MIN(match_priority) AS best
    FROM xml_ranked
    GROUP BY opinion_id
),

xml_best_candidates AS (
    SELECT r.*
    FROM xml_ranked r
    JOIN xml_best_priority bp
      ON bp.opinion_id = r.opinion_id
     AND bp.best = r.match_priority
),

xml_aggregated AS (
    SELECT
        x.opinion_id,
        x.raw_author_tag              AS xml_raw_author_tag,
        x.clean_author_tag            AS xml_clean_author_tag,
        x.extracted_author_name       AS xml_extracted_author_name,
        x.xml_name_without_suffix,
        x.xml_last_name_norm,
        x.xml_full_name_norm,
        x.xml_first_initial,
        x.xml_middle_initial,
        x.xml_is_initial_name,
        x.xml_fjc_court_name,

        MIN(bc.match_priority)  AS xml_best_match_priority,
        COUNT(DISTINCT bc.judge_id) AS xml_n_candidate_judges,
        COUNT(DISTINCT bc.gender) FILTER (WHERE bc.gender IS NOT NULL
            AND BTRIM(bc.gender) <> '') AS xml_n_candidate_genders,
        STRING_AGG(DISTINCT bc.display_name, ' | ' ORDER BY bc.display_name) AS xml_candidate_names,
        STRING_AGG(DISTINCT bc.judge_id,     ' | ' ORDER BY bc.judge_id)     AS xml_candidate_nids,
        STRING_AGG(DISTINCT bc.gender,       ' | ' ORDER BY bc.gender)       AS xml_candidate_genders,
        MIN(bc.gender) FILTER (WHERE bc.gender IS NOT NULL
            AND BTRIM(bc.gender) <> '') AS xml_gender_if_unique

    FROM xml_normed x
    LEFT JOIN xml_best_candidates bc ON bc.opinion_id = x.opinion_id
    GROUP BY
        x.opinion_id, x.raw_author_tag, x.clean_author_tag,
        x.extracted_author_name, x.xml_name_without_suffix,
        x.xml_last_name_norm, x.xml_full_name_norm,
        x.xml_first_initial, x.xml_middle_initial,
        x.xml_is_initial_name, x.xml_fjc_court_name
),

-- ===========================================================
-- 3. HTML branch  –  extract from html_with_citations
--    Restricted to year_filed >= 1960
-- ===========================================================

-- 3a. Pre-process HTML: classify type, build stripped text variants.
--
-- Non-Harvard types:
--   html_text_flat  – whitespace-normalised text for paragraph-level patterns.
--   html_text_lines – line-preserving text for line-level attribution patterns.
--
-- Harvard structured:
--   raw HTML is preserved; A10/A11 operate directly on html_with_citations.
html_prepared AS (
    SELECT
        b.*,
        CASE
            WHEN b.html_with_citations ~* 'class="indent"'                THEN 'harvard_structured'
            WHEN b.html_with_citations ~* '^\s*<\?xml'                    THEN 'xml_inline'
            WHEN b.html_with_citations ~* '^\s*<pre\s[^>]*class="inline"' THEN 'pre_inline'
            ELSE 'plain_html'
        END AS html_type,

        -- Flat stripped text – used only for non-Harvard fallback patterns.
        CASE WHEN b.html_with_citations !~* 'class="indent"' THEN
            LEFT(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(b.html_with_citations, ''),
                            '</p>|</div>|<br\s*/?>|</blockquote>|</center>',
                            E'\n', 'gi'),
                        '<[^>]+>', ' ', 'g'),
                    '[[:space:]]+', ' ', 'g'),
                8000)
        END AS html_text_flat,

        -- Line-preserving text – used for attribution lines.
        CASE WHEN b.html_with_citations !~* 'class="indent"' THEN
            LEFT(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        COALESCE(b.html_with_citations, ''),
                        '</p>|</div>|<br\s*/?>|</blockquote>|</center>',
                        E'\n', 'gi'),
                    '<[^>]+>', ' ', 'g'),
                8000)
        END AS html_text_lines

    FROM base b
    WHERE b.year_filed >= 1960
      AND b.html_with_citations IS NOT NULL
      AND BTRIM(b.html_with_citations) <> ''
),

-- 3b. Extract author name using ordered LATERAL candidates.
--
-- Design:
--   Strong patterns:
--     A1  Opinion by Judge NAME
--     A2  Opinion by NAME, Circuit/District Judge
--     A6  Judge NAME delivered the opinion
--
--   Weak line patterns:
--     A3  NAME, Circuit/District Judge
--     A4  NAME, Chief/Senior Judge
--
--   Weak line patterns are filtered conservatively because many
--   opinions list panel judges before the true author attribution.
--
-- Important fixes:
--   - pre_inline A3 only accepts Circuit Judge, not District Judge.
--   - A3/A4 require Judge followed by ":" or ".".
--   - A3/A4 allow opinion text after "Judge.", e.g.
--       MAGILL, Senior Circuit Judge. Manuel Morillo pleaded ...
--   - Panel artifacts with "and", semicolons, or comma-lists are removed.
html_extracted AS (
    SELECT
        h.opinion_id,
        h.cluster_id,
        h.docket_id,
        h.court_id,
        h.court_short_name,
        h.date_filed,
        h.year_filed,
        h.case_name,
        h.opinion_type,
        h.precedential_status,
        h.per_curiam,
        h.html_type,
        m.extracted_author_name_raw,
        m.html_extraction_pattern

    FROM html_prepared h
    LEFT JOIN LATERAL (
        WITH
        -- Split line-preserving text once.
        lines AS (
            SELECT
                l.line_no,
                BTRIM(l.line) AS line_txt,
                MAX(CASE
                        WHEN BTRIM(l.line) ~* '^Before\s*:'
                        THEN l.line_no
                    END) OVER (
                        ORDER BY l.line_no
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                    ) AS last_before_line_no
            FROM regexp_split_to_table(COALESCE(h.html_text_lines, ''), E'\n')
                 WITH ORDINALITY AS l(line, line_no)
            WHERE h.html_type <> 'harvard_structured'
        ),

        -- Strong line-based patterns.
        strong_line_matches AS (
            -- A1: "Opinion by [Chief/Senior] [Circuit] Judge NAME"
            SELECT
                10 AS priority,
                l.line_no,
                NULLIF(BTRIM((REGEXP_MATCH(l.line_txt,
                    $re$(?i)^\s*Opinion\s+by\s+(?:Chief\s+|Senior\s+)?(?:Circuit\s+)?Judge\s+([A-Z][A-Za-z.'[:blank:]-]{1,60}?)\s*[:.]?\s*$re$
                ))[1]), '') AS v,
                'A1_opinion_by_judge_name' AS pat
            FROM lines l
            WHERE l.line_txt ~* $re$^\s*Opinion\s+by\s+(?:Chief\s+|Senior\s+)?(?:Circuit\s+)?Judge\s+[A-Z]$re$

            UNION ALL

            -- A2: "Opinion by NAME, [Chief/Senior] [Circuit/District] Judge"
            SELECT
                20 AS priority,
                l.line_no,
                NULLIF(BTRIM((REGEXP_MATCH(l.line_txt,
                    $re$(?i)^\s*Opinion\s+by\s+([A-Z][A-Za-z.'[:blank:]-]{2,60}?),\s*(?:Chief\s+|Senior\s+)?(?:Circuit|District)\s+Judge\s*[:.]?\s*$re$
                ))[1]), '') AS v,
                'A2_opinion_by_name_circuit_or_district_judge' AS pat
            FROM lines l
            WHERE l.line_txt ~* $re$^\s*Opinion\s+by\s+[A-Z]$re$
        ),

        -- Strong flat-text fallback.
        strong_flat_matches AS (
            -- A6: "Judge NAME delivered the opinion"
            SELECT
                30 AS priority,
                NULL::bigint AS line_no,
                NULLIF(BTRIM((REGEXP_MATCH(h.html_text_flat,
                    $$(?i)\bJudge\s+([A-Z][A-Za-z.'\s-]{2,60}?)\s+delivered\s+the\s+opinion\b$$
                ))[1]), '') AS v,
                'A6_judge_delivered_opinion' AS pat
            WHERE h.html_type <> 'harvard_structured'
        ),

        -- Weak line patterns with panel-header safeguards.
        weak_line_matches AS (
            -- A3a: non-pre_inline only.
            -- Allows Circuit/District Judge for plain_html and xml_inline.
            -- Allows text after "Judge." on the same line.
            SELECT
                40 AS priority,
                l.line_no,
                NULLIF(BTRIM((REGEXP_MATCH(l.line_txt,
                    $re$(?i)^\s*(?:[_[:blank:]]+)?([A-Z][A-Za-z.'[:blank:]-]{2,80}?),\s*(?:Chief\s+|Senior\s+)?(?:Circuit|District)\s+Judge\s*[:.](?:\s|$)$re$
                ))[1]), '') AS v,
                'A3_name_circuit_or_district_judge_line_non_pre_inline' AS pat
            FROM lines l
            WHERE h.html_type IN ('plain_html', 'xml_inline')
              AND l.line_txt ~* $re$^\s*(?:[_[:blank:]]+)?[A-Z][A-Za-z.'[:blank:]-]{2,80}?,\s*(?:Chief\s+|Senior\s+)?(?:Circuit|District)\s+Judge\s*[:.](?:\s|$)$re$
              AND (
                    l.last_before_line_no IS NULL
                    OR l.line_no - l.last_before_line_no > 5
                  )

            UNION ALL

            -- A3b: pre_inline-safe version.
            -- Critical: Circuit Judge only. District Judge in pre_inline often
            -- names the lower-court presiding judge rather than the appellate author.
            SELECT
                41 AS priority,
                l.line_no,
                NULLIF(BTRIM((REGEXP_MATCH(l.line_txt,
                    $re$(?i)^\s*(?:[_[:blank:]]+)?([A-Z][A-Za-z.'[:blank:]-]{2,80}?),\s*(?:Chief\s+|Senior\s+)?Circuit\s+Judge\s*[:.](?:\s|$)$re$
                ))[1]), '') AS v,
                'A3_circuit_judge_line_pre_inline' AS pat
            FROM lines l
            WHERE h.html_type = 'pre_inline'
              AND l.line_txt ~* $re$^\s*(?:[_[:blank:]]+)?[A-Z][A-Za-z.'[:blank:]-]{2,80}?,\s*(?:Chief\s+|Senior\s+)?Circuit\s+Judge\s*[:.](?:\s|$)$re$
              AND (
                    l.last_before_line_no IS NULL
                    OR l.line_no - l.last_before_line_no > 5
                  )

            UNION ALL

            -- A4: "NAME, Chief Judge." or "NAME, Senior Judge."
            -- Disabled for pre_inline because unqualified Chief/Senior Judge
            -- lines are too easy to confuse with header material.
            SELECT
                50 AS priority,
                l.line_no,
                NULLIF(BTRIM((REGEXP_MATCH(l.line_txt,
                    $re$(?i)^\s*(?:[_[:blank:]]+)?([A-Z][A-Za-z.'[:blank:]-]{2,80}?),\s*(?:Chief|Senior)\s+Judge\s*[:.](?:\s|$)$re$
                ))[1]), '') AS v,
                'A4_name_chief_senior_judge_line_non_pre_inline' AS pat
            FROM lines l
            WHERE h.html_type IN ('plain_html', 'xml_inline')
              AND l.line_txt ~* $re$^\s*(?:[_[:blank:]]+)?[A-Z][A-Za-z.'[:blank:]-]{2,80}?,\s*(?:Chief|Senior)\s+Judge\s*[:.](?:\s|$)$re$
              AND (
                    l.last_before_line_no IS NULL
                    OR l.line_no - l.last_before_line_no > 5
                  )
        ),

        -- Harvard structured patterns.
        harvard_matches AS (
            -- A10: Harvard: after <p>OPINION</p>, first class="indent" paragraph with judge name
            SELECT
                60 AS priority,
                NULL::bigint AS line_no,
                NULLIF(BTRIM((REGEXP_MATCH(LEFT(h.html_with_citations, 15000),
                    $$(?is)<p[^>]*>\s*OPINION\s*</p>\s*(?:<[^>]+>\s*)*<p[^>]+class="indent"[^>]*>\s*([A-Z][A-Za-z\s.',III Jr Sr-]{2,80}?),\s*(?:Chief\s+)?(?:Senior\s+)?(?:Circuit|District|Senior)\s+Judge\s*[.:]?\s*</p>$$
                ))[1]), '') AS v,
                'A10_harvard_opinion_indent' AS pat
            WHERE h.html_type = 'harvard_structured'

            UNION ALL

            -- A11: Harvard: first class="indent" paragraph with judge name
            SELECT
                70 AS priority,
                NULL::bigint AS line_no,
                NULLIF(BTRIM((REGEXP_MATCH(LEFT(h.html_with_citations, 15000),
                    $$(?is)<p[^>]+class="indent"[^>]*>\s*([A-Z][A-Za-z\s.',III Jr Sr-]{2,80}?),\s*(?:Chief\s+)?(?:Senior\s+)?(?:Circuit|District|Senior)\s+Judge\s*[.:]?\s*</p>$$
                ))[1]), '') AS v,
                'A11_harvard_first_indent' AS pat
            WHERE h.html_type = 'harvard_structured'
        ),

        all_matches AS (
            SELECT * FROM strong_line_matches
            UNION ALL
            SELECT * FROM strong_flat_matches
            UNION ALL
            SELECT * FROM weak_line_matches
            UNION ALL
            SELECT * FROM harvard_matches
        ),

        cleaned_matches AS (
            SELECT
                priority,
                line_no,
                BTRIM(v) AS v,
                pat
            FROM all_matches
            WHERE v IS NOT NULL
              AND BTRIM(v) <> ''

              -- Exclude multi-judge/panel captures, e.g. "CHIN and CARNEY"
              AND BTRIM(v) !~* '(^|[[:space:]])and[[:space:]]'

              -- Exclude semicolon list artifacts
              AND BTRIM(v) !~* ';'

              -- Exclude comma-list artifacts, but allow suffixes such as "WOOD, Jr."
              AND (
                    BTRIM(v) !~ ','
                    OR BTRIM(v) ~* ',[[:space:]]*(Jr\.?|Sr\.?|II|III|IV|V)$'
                  )

              -- Exclude obvious panel words if they leak into capture
              AND BTRIM(v) !~* '(^|[^[:alpha:]])(Before|Circuit Judges|District Judges)([^[:alpha:]]|$)'
        )

        SELECT
            v AS extracted_author_name_raw,
            pat AS html_extraction_pattern
        FROM cleaned_matches
        ORDER BY priority, line_no NULLS LAST
        LIMIT 1
    ) m ON TRUE
),

-- 3c. Filter and extract last line.
-- Mostly a safety layer. The new extraction is line-based, but this
-- keeps protection against residual multiline or panel-list artifacts.
html_last_line AS (
    SELECT
        *,
        BTRIM(REGEXP_REPLACE(
            BTRIM(COALESCE(extracted_author_name_raw, '')),
            '^.*\n\s*', '', 's'
        )) AS extracted_author_last_line
    FROM html_extracted
    WHERE extracted_author_name_raw IS NOT NULL
      AND LENGTH(BTRIM(COALESCE(extracted_author_name_raw, ''))) BETWEEN 3 AND 80
      AND BTRIM(COALESCE(extracted_author_name_raw, '')) ~ '[[:alpha:]]'

      -- Exclude collective/procedural labels
      AND BTRIM(COALESCE(extracted_author_name_raw, ''))
          !~* '^\s*(PER CURIAM|MEMORANDUM|ORDER|THE COURT|OPINION|DISSENT|CONCURRENCE|SYLLABUS|SUMMARY)\s*$'

      -- Exclude party/litigation artifacts
      AND BTRIM(COALESCE(extracted_author_name_raw, ''))
          !~* '\b(plaintiff|defendant|appellant|appellee|petitioner|respondent|united\s+states|commission|board|department)\b'

      -- Exclude panel-header artifacts
      AND BTRIM(COALESCE(extracted_author_name_raw, ''))
          !~* '^\s*Before[[:space:]:]'
      AND BTRIM(COALESCE(extracted_author_name_raw, ''))
          !~* '(^|[[:space:]])and[[:space:]]'
      AND BTRIM(COALESCE(extracted_author_name_raw, ''))
          !~* ';'
      AND (
            BTRIM(COALESCE(extracted_author_name_raw, '')) !~ ','
            OR BTRIM(COALESCE(extracted_author_name_raw, '')) ~* ',[[:space:]]*(Jr\.?|Sr\.?|II|III|IV|V)$'
          )
),

-- 3d. Normalise HTML name – includes compound-name and suffix fixes
--     previously handled as patches in 19c.
html_normed AS (
    SELECT
        opinion_id,
        cluster_id,
        docket_id,
        court_id,
        court_short_name,
        date_filed,
        year_filed,
        case_name,
        opinion_type,
        precedential_status,
        per_curiam,
        html_type,
        html_extraction_pattern,

        -- Final author name.
        -- Strip residual judge title if the regex leaked it.
        BTRIM(REGEXP_REPLACE(
            extracted_author_last_line,
            ',?\s*(?:Chief\s+)?(?:Senior\s+)?(?:Circuit|District|Senior)\s+Judge[.:]?\s*$',
            '', 'i'
        )) AS extracted_author_name,

        -- Last-name norm: last word after suffix removal.
        LOWER(REGEXP_REPLACE(
            SPLIT_PART(
                REGEXP_REPLACE(
                    BTRIM(COALESCE(extracted_author_last_line, '')),
                    $re$\s*,?\s*\b(?:Jr\.?|Sr\.?|II|III|IV|V)\s*$$re$, '', 'i'),
                ' ',
                GREATEST(
                    array_length(
                        string_to_array(
                            REGEXP_REPLACE(
                                BTRIM(COALESCE(extracted_author_last_line, '')),
                                $re$\s*,?\s*\b(?:Jr\.?|Sr\.?|II|III|IV|V)\s*$$re$, '', 'i'),
                            ' '),
                        1),
                    1)
            ),
            '[^a-zA-Z]', '', 'g'
        )) AS extracted_author_last_name_norm,

        -- Full-name norm.
        LOWER(REGEXP_REPLACE(
            BTRIM(COALESCE(extracted_author_last_line, '')),
            '[^[:alpha:]]', '', 'g'
        )) AS extracted_author_full_name_norm,

        -- First initial.
        LOWER(SUBSTRING(
            REGEXP_REPLACE(
                BTRIM(COALESCE(extracted_author_last_line, '')),
                '^[^a-zA-Z]+', '')
            FROM 1 FOR 1
        )) AS extracted_first_initial,

        -- Middle initial.
        CASE
            WHEN BTRIM(COALESCE(extracted_author_last_line, ''))
                 ~* '^[[:alpha:]][.]?[[:space:]]*[[:alpha:]]?[.]?[[:space:]]+'
                THEN LOWER(SUBSTRING(
                    BTRIM(COALESCE(extracted_author_last_line, ''))
                    FROM '^[[:alpha:]][.]?[[:space:]]*([[:alpha:]])[.]?[[:space:]]+'
                ))
            ELSE NULL
        END AS extracted_middle_initial,

        -- Is initial-form name?
        CASE
            WHEN BTRIM(COALESCE(extracted_author_last_line, ''))
                 ~* '^[[:alpha:]][.]?[[:space:]]*[[:alpha:]]?[.]?[[:space:]]+[[:alpha:]]+$'
                THEN TRUE
            ELSE FALSE
        END AS extracted_is_initial_name,

        -- Compound-name norm.
        -- full_name_as_last_norm matches pool last_name_norm for compound surnames.
        LOWER(REGEXP_REPLACE(
            BTRIM(COALESCE(extracted_author_last_line, '')),
            '[^[:alpha:]]', '', 'g'
        )) AS full_name_as_last_norm,

        -- Suffix-stripped last-name norm.
        LOWER(REGEXP_REPLACE(
            COALESCE(
                (regexp_match(
                    REGEXP_REPLACE(
                        BTRIM(COALESCE(
                            BTRIM(REGEXP_REPLACE(
                                extracted_author_last_line,
                                ',?\s*(?:Chief\s+)?(?:Senior\s+)?(?:Circuit|District|Senior)\s+Judge[.:]?\s*$',
                                '', 'i')),
                            extracted_author_last_line)),
                        '\,?\s+(Jr\.?|JR\.?|Sr\.?|SR\.?|II|III|IV|V|2nd|3rd)\s*$',
                        '', 'gi'),
                    '(\S+)\s*$'))[1],
                ''),
            '[^[:alpha:]]', '', 'g'
        )) AS suffix_stripped_last_norm

    FROM html_last_line

    -- Exclude residual panel-list artifacts:
    --   "and Stahl"
    --   "CHIN and CARNEY"
    --   comma/semicolon panel lists
    WHERE extracted_author_last_line !~* '^\s*and[[:space:]]'
      AND extracted_author_last_line !~* '(^|[[:space:]])and[[:space:]]'
      AND extracted_author_last_line !~* ';'
      AND (
            extracted_author_last_line !~ ','
            OR extracted_author_last_line ~* ',[[:space:]]*(Jr\.?|Sr\.?|II|III|IV|V)$'
          )
),

html_with_court AS (
    SELECT hn.*, cm.fjc_court_name AS html_fjc_court_name
    FROM html_normed hn
    LEFT JOIN ext.fjc_court_name_map cm ON cm.court_id = hn.court_id
),

-- 3e. Match HTML names against judge pool.
--     Tiers 1-8: standard matching.
--     Tier 9:    compound last name.
--     Tier 10:   suffix-stripped + active period.
--     Tier 11:   suffix-stripped.
html_candidates AS (
    SELECT
        x.opinion_id,
        f.judge_id,
        f.gender,
        f.full_name_norm,
        f.last_name_norm,
        f.first_initial,
        f.mid_initial,
        f.display_name,
        CASE
            WHEN f.full_name_norm = x.extracted_author_full_name_norm
             AND f.court_id = x.court_id
                THEN 'exact_full_name_same_court'

            WHEN x.extracted_is_initial_name = TRUE
             AND f.last_name_norm = x.extracted_author_last_name_norm
             AND f.first_initial  = x.extracted_first_initial
             AND (x.extracted_middle_initial IS NULL OR x.extracted_middle_initial = ''
                  OR f.mid_initial = x.extracted_middle_initial)
             AND f.court_id = x.court_id
                THEN 'initials_last_name_same_court'

            WHEN f.full_name_norm = x.extracted_author_full_name_norm
                THEN 'exact_full_name_any_court'

            WHEN x.extracted_is_initial_name = TRUE
             AND f.last_name_norm = x.extracted_author_last_name_norm
             AND f.first_initial  = x.extracted_first_initial
             AND (x.extracted_middle_initial IS NULL OR x.extracted_middle_initial = ''
                  OR f.mid_initial = x.extracted_middle_initial)
                THEN 'initials_last_name_any_court'

            WHEN f.last_name_norm = x.extracted_author_last_name_norm
             AND f.court_id = x.court_id
             AND (f.start_date IS NULL
                  OR EXTRACT(YEAR FROM f.start_date) <= x.year_filed)
             AND (f.end_date IS NULL
                  OR EXTRACT(YEAR FROM f.end_date) >= x.year_filed)
             AND (x.extracted_author_full_name_norm = x.extracted_author_last_name_norm
                  OR x.extracted_first_initial IS NULL OR x.extracted_first_initial = ''
                  OR f.first_initial = x.extracted_first_initial)
                THEN 'last_name_same_court_active_period'

            WHEN f.last_name_norm = x.extracted_author_last_name_norm
             AND f.court_id = x.court_id
             AND (x.extracted_author_full_name_norm = x.extracted_author_last_name_norm
                  OR x.extracted_first_initial IS NULL OR x.extracted_first_initial = ''
                  OR f.first_initial = x.extracted_first_initial)
                THEN 'last_name_same_court'

            WHEN f.last_name_norm = x.extracted_author_last_name_norm
             AND (f.start_date IS NULL
                  OR EXTRACT(YEAR FROM f.start_date) <= x.year_filed)
             AND (f.end_date IS NULL
                  OR EXTRACT(YEAR FROM f.end_date) >= x.year_filed)
             AND (x.extracted_author_full_name_norm = x.extracted_author_last_name_norm
                  OR x.extracted_first_initial IS NULL OR x.extracted_first_initial = ''
                  OR f.first_initial = x.extracted_first_initial)
                THEN 'last_name_any_court_active_period'

            WHEN f.last_name_norm = x.extracted_author_last_name_norm
             AND (x.extracted_author_full_name_norm = x.extracted_author_last_name_norm
                  OR x.extracted_first_initial IS NULL OR x.extracted_first_initial = ''
                  OR f.first_initial = x.extracted_first_initial)
                THEN 'last_name_any_court'

            -- Compound last name, e.g. VAN GRAAFEILAND, ST. EVE.
            WHEN f.last_name_norm = x.full_name_as_last_norm
             AND x.full_name_as_last_norm <> x.extracted_author_last_name_norm
             AND f.court_id = x.court_id
                THEN 'compound_last_same_court'

            -- Suffix-stripped last name, same court, active period.
            WHEN f.last_name_norm = x.suffix_stripped_last_norm
             AND x.suffix_stripped_last_norm IS NOT NULL
             AND x.suffix_stripped_last_norm <> ''
             AND x.suffix_stripped_last_norm <> x.extracted_author_last_name_norm
             AND f.court_id = x.court_id
             AND (f.start_date IS NULL
                  OR EXTRACT(YEAR FROM f.start_date) <= x.year_filed)
             AND (f.end_date IS NULL
                  OR EXTRACT(YEAR FROM f.end_date) >= x.year_filed)
             AND (x.extracted_first_initial IS NULL OR x.extracted_first_initial = ''
                  OR f.first_initial = x.extracted_first_initial)
                THEN 'suffix_stripped_last_same_court_active_period'

            -- Suffix-stripped last name, same court, no temporal filter.
            WHEN f.last_name_norm = x.suffix_stripped_last_norm
             AND x.suffix_stripped_last_norm IS NOT NULL
             AND x.suffix_stripped_last_norm <> ''
             AND x.suffix_stripped_last_norm <> x.extracted_author_last_name_norm
             AND f.court_id = x.court_id
             AND (x.extracted_first_initial IS NULL OR x.extracted_first_initial = ''
                  OR f.first_initial = x.extracted_first_initial)
                THEN 'suffix_stripped_last_same_court'

            ELSE NULL
        END AS match_type

    FROM html_with_court x
    JOIN all_judges f
      ON (   f.full_name_norm = x.extracted_author_full_name_norm
          OR f.last_name_norm = x.extracted_author_last_name_norm
          OR (f.last_name_norm = x.full_name_as_last_norm
              AND x.full_name_as_last_norm <> x.extracted_author_last_name_norm)
          OR (f.last_name_norm = x.suffix_stripped_last_norm
              AND x.suffix_stripped_last_norm IS NOT NULL
              AND x.suffix_stripped_last_norm <> ''
              AND x.suffix_stripped_last_norm <> x.extracted_author_last_name_norm))
    WHERE x.extracted_author_last_name_norm IS NOT NULL
      AND x.extracted_author_last_name_norm <> ''
),

html_ranked AS (
    SELECT *,
        CASE match_type
            WHEN 'exact_full_name_same_court'                    THEN 1
            WHEN 'initials_last_name_same_court'                 THEN 2
            WHEN 'exact_full_name_any_court'                     THEN 3
            WHEN 'initials_last_name_any_court'                  THEN 4
            WHEN 'last_name_same_court_active_period'            THEN 5
            WHEN 'last_name_same_court'                          THEN 6
            WHEN 'last_name_any_court_active_period'             THEN 7
            WHEN 'last_name_any_court'                           THEN 8
            WHEN 'compound_last_same_court'                      THEN 9
            WHEN 'suffix_stripped_last_same_court_active_period' THEN 10
            WHEN 'suffix_stripped_last_same_court'               THEN 11
            ELSE 99
        END AS match_priority
    FROM html_candidates
    WHERE match_type IS NOT NULL
),

html_best_priority AS (
    SELECT opinion_id, MIN(match_priority) AS best
    FROM html_ranked
    GROUP BY opinion_id
),

html_best_candidates AS (
    SELECT r.*
    FROM html_ranked r
    JOIN html_best_priority bp
      ON bp.opinion_id = r.opinion_id
     AND bp.best = r.match_priority
),

html_aggregated AS (
    SELECT
        n.opinion_id,
        n.html_type,
        n.html_extraction_pattern,
        n.extracted_author_name           AS html_extracted_author_name,
        n.extracted_author_last_name_norm AS html_last_name_norm,
        n.extracted_author_full_name_norm AS html_full_name_norm,
        n.extracted_first_initial         AS html_first_initial,
        n.extracted_middle_initial        AS html_middle_initial,
        n.extracted_is_initial_name       AS html_is_initial_name,
        n.html_fjc_court_name,

        MIN(bc.match_priority) AS html_best_match_priority,
        COUNT(DISTINCT bc.judge_id) AS html_n_candidate_judges,
        COUNT(DISTINCT bc.gender) FILTER (
            WHERE bc.gender IS NOT NULL
              AND BTRIM(bc.gender) <> ''
        ) AS html_n_candidate_genders,
        STRING_AGG(DISTINCT bc.display_name, ' | ' ORDER BY bc.display_name) AS html_candidate_names,
        STRING_AGG(DISTINCT bc.judge_id,     ' | ' ORDER BY bc.judge_id)     AS html_candidate_nids,
        STRING_AGG(DISTINCT bc.gender,       ' | ' ORDER BY bc.gender)       AS html_candidate_genders,
        MIN(bc.gender) FILTER (
            WHERE bc.gender IS NOT NULL
              AND BTRIM(bc.gender) <> ''
        ) AS html_gender_if_unique

    FROM html_with_court n
    LEFT JOIN html_best_candidates bc ON bc.opinion_id = n.opinion_id
    GROUP BY
        n.opinion_id,
        n.html_type,
        n.html_extraction_pattern,
        n.extracted_author_name,
        n.extracted_author_last_name_norm,
        n.extracted_author_full_name_norm,
        n.extracted_first_initial,
        n.extracted_middle_initial,
        n.extracted_is_initial_name,
        n.html_fjc_court_name
),

-- ===========================================================
-- 4. Final assembly: XML priority over HTML
-- ===========================================================
result AS (
    SELECT
        b.opinion_id,
        b.cluster_id,
        b.docket_id,
        b.court_id,
        b.court_short_name,
        b.date_filed,
        b.year_filed,
        b.case_name,
        b.opinion_type,
        b.precedential_status,
        b.per_curiam,
        b.author_id,
        b.author_str,

        -- --------------------------------------------------------
        -- XML diagnostics
        -- --------------------------------------------------------
        xa.xml_raw_author_tag,
        xa.xml_clean_author_tag,
        xa.xml_extracted_author_name,
        xa.xml_name_without_suffix,
        xa.xml_last_name_norm               AS xml_extracted_author_last_name_norm,
        xa.xml_full_name_norm               AS xml_extracted_author_full_name_norm,
        xa.xml_first_initial,
        xa.xml_middle_initial,
        xa.xml_is_initial_name,
        xa.xml_fjc_court_name,
        COALESCE(xa.xml_n_candidate_judges,  0) AS xml_n_candidate_judges,
        COALESCE(xa.xml_n_candidate_genders, 0) AS xml_n_candidate_genders,
        xa.xml_candidate_names,
        xa.xml_candidate_nids,
        xa.xml_candidate_genders,
        xa.xml_best_match_priority,

        CASE WHEN COALESCE(xa.xml_n_candidate_genders, 0) = 1
            THEN xa.xml_gender_if_unique ELSE NULL END AS xml_gender,
        CASE WHEN COALESCE(xa.xml_n_candidate_genders, 0) = 1
            THEN TRUE ELSE FALSE END AS xml_gender_resolved,

        CASE
            WHEN xa.xml_best_match_priority = 1 AND xa.xml_n_candidate_judges = 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_author_tag_fjc_exact_full_name_same_court_unique_judge'
            WHEN xa.xml_best_match_priority = 1 AND xa.xml_n_candidate_judges > 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_author_tag_fjc_exact_full_name_same_court_unique_gender'
            WHEN xa.xml_best_match_priority = 2 AND xa.xml_n_candidate_judges = 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_author_tag_fjc_initials_last_name_same_court_unique_judge'
            WHEN xa.xml_best_match_priority = 2 AND xa.xml_n_candidate_judges > 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_author_tag_fjc_initials_last_name_same_court_unique_gender'
            WHEN xa.xml_best_match_priority = 3 AND xa.xml_n_candidate_judges = 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_author_tag_fjc_exact_full_name_any_court_unique_judge'
            WHEN xa.xml_best_match_priority = 3 AND xa.xml_n_candidate_judges > 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_author_tag_fjc_exact_full_name_any_court_unique_gender'
            WHEN xa.xml_best_match_priority = 4 AND xa.xml_n_candidate_judges = 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_author_tag_fjc_initials_last_name_any_court_unique_judge'
            WHEN xa.xml_best_match_priority = 4 AND xa.xml_n_candidate_judges > 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_author_tag_fjc_initials_last_name_any_court_unique_gender'
            WHEN xa.xml_best_match_priority = 5 AND xa.xml_n_candidate_judges = 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_author_tag_fjc_last_name_same_court_active_period_unique_judge'
            WHEN xa.xml_best_match_priority = 5 AND xa.xml_n_candidate_judges > 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_author_tag_fjc_last_name_same_court_active_period_unique_gender'
            WHEN xa.xml_best_match_priority = 6 AND xa.xml_n_candidate_judges = 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_author_tag_fjc_last_name_same_court_unique_judge'
            WHEN xa.xml_best_match_priority = 6 AND xa.xml_n_candidate_judges > 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_author_tag_fjc_last_name_same_court_unique_gender'
            WHEN COALESCE(xa.xml_n_candidate_judges, 0) > 0
             AND COALESCE(xa.xml_n_candidate_genders, 0) > 1
                THEN 'xml_author_tag_fjc_ambiguous_multiple_genders'
            WHEN COALESCE(xa.xml_n_candidate_judges, 0) > 0
             AND COALESCE(xa.xml_n_candidate_genders, 0) = 0
                THEN 'xml_author_tag_fjc_candidates_without_gender'
            WHEN xa.xml_extracted_author_name IS NOT NULL
                THEN 'xml_author_tag_judge_no_match'
            ELSE NULL
        END AS xml_gender_source,

        CASE
            WHEN xa.xml_best_match_priority = 1 AND xa.xml_n_candidate_judges = 1
             AND xa.xml_n_candidate_genders = 1 THEN 5
            WHEN xa.xml_best_match_priority = 1 AND xa.xml_n_candidate_judges > 1
             AND xa.xml_n_candidate_genders = 1 THEN 6
            WHEN xa.xml_best_match_priority = 2 AND xa.xml_n_candidate_genders = 1 THEN 7
            WHEN xa.xml_best_match_priority = 3 AND xa.xml_n_candidate_genders = 1 THEN 8
            WHEN xa.xml_best_match_priority = 4 AND xa.xml_n_candidate_genders = 1 THEN 9
            WHEN xa.xml_best_match_priority = 5 AND xa.xml_n_candidate_genders = 1 THEN 11
            WHEN xa.xml_best_match_priority = 6 AND xa.xml_n_candidate_genders = 1 THEN 12
            WHEN COALESCE(xa.xml_n_candidate_judges, 0) > 0
             AND COALESCE(xa.xml_n_candidate_genders, 0) > 1  THEN 90
            WHEN COALESCE(xa.xml_n_candidate_judges, 0) > 0
             AND COALESCE(xa.xml_n_candidate_genders, 0) = 0  THEN 91
            ELSE 99
        END AS xml_gender_match_quality_tier,

        CASE
            WHEN xa.xml_best_match_priority = 1 AND xa.xml_n_candidate_judges = 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_exact_full_name_same_court_unique_judge'
            WHEN xa.xml_best_match_priority = 1 AND xa.xml_n_candidate_judges > 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_exact_full_name_same_court_unique_gender'
            WHEN xa.xml_best_match_priority = 2 AND xa.xml_n_candidate_judges = 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_initials_last_name_same_court_unique_judge'
            WHEN xa.xml_best_match_priority = 2 AND xa.xml_n_candidate_judges > 1
             AND xa.xml_n_candidate_genders = 1
                THEN 'xml_initials_last_name_same_court_unique_gender'
            WHEN xa.xml_best_match_priority = 3 AND xa.xml_n_candidate_genders = 1
                THEN 'xml_exact_full_name_any_court_unique_gender'
            WHEN xa.xml_best_match_priority = 4 AND xa.xml_n_candidate_genders = 1
                THEN 'xml_initials_last_name_any_court_unique_gender'
            WHEN xa.xml_best_match_priority = 5 AND xa.xml_n_candidate_genders = 1
                THEN 'xml_last_name_same_court_active_period_unique_gender'
            WHEN xa.xml_best_match_priority = 6 AND xa.xml_n_candidate_genders = 1
                THEN 'xml_last_name_same_court_unique_gender'
            WHEN COALESCE(xa.xml_n_candidate_judges, 0) > 0
             AND COALESCE(xa.xml_n_candidate_genders, 0) > 1
                THEN 'xml_ambiguous_multiple_genders'
            WHEN COALESCE(xa.xml_n_candidate_judges, 0) > 0
             AND COALESCE(xa.xml_n_candidate_genders, 0) = 0
                THEN 'xml_candidates_without_gender'
            ELSE 'xml_no_judge_match'
        END AS xml_gender_match_quality_label,

        -- --------------------------------------------------------
        -- HTML diagnostics
        -- --------------------------------------------------------
        ha.html_type,
        ha.html_extraction_pattern,
        ha.html_extracted_author_name,
        ha.html_last_name_norm          AS html_extracted_author_last_name_norm,
        ha.html_full_name_norm,
        ha.html_first_initial,
        ha.html_middle_initial,
        ha.html_is_initial_name,
        ha.html_fjc_court_name,
        COALESCE(ha.html_n_candidate_judges,  0) AS html_n_candidate_judges,
        COALESCE(ha.html_n_candidate_genders, 0) AS html_n_candidate_genders,
        ha.html_candidate_names,
        ha.html_candidate_nids,
        ha.html_candidate_genders,
        ha.html_best_match_priority,

        CASE WHEN COALESCE(ha.html_n_candidate_genders, 0) = 1
            THEN ha.html_gender_if_unique ELSE NULL END AS html_gender,
        CASE WHEN COALESCE(ha.html_n_candidate_genders, 0) = 1
            THEN TRUE ELSE FALSE END AS html_gender_resolved,

        CASE
            WHEN ha.html_best_match_priority = 1 AND ha.html_n_candidate_judges = 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_exact_full_name_same_court_unique_judge'
            WHEN ha.html_best_match_priority = 1 AND ha.html_n_candidate_judges > 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_exact_full_name_same_court_unique_gender'
            WHEN ha.html_best_match_priority = 2 AND ha.html_n_candidate_judges = 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_initials_last_name_same_court_unique_judge'
            WHEN ha.html_best_match_priority = 2 AND ha.html_n_candidate_judges > 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_initials_last_name_same_court_unique_gender'
            WHEN ha.html_best_match_priority = 3 AND ha.html_n_candidate_judges = 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_exact_full_name_any_court_unique_judge'
            WHEN ha.html_best_match_priority = 3 AND ha.html_n_candidate_judges > 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_exact_full_name_any_court_unique_gender'
            WHEN ha.html_best_match_priority = 4 AND ha.html_n_candidate_judges = 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_initials_last_name_any_court_unique_judge'
            WHEN ha.html_best_match_priority = 4 AND ha.html_n_candidate_judges > 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_initials_last_name_any_court_unique_gender'
            WHEN ha.html_best_match_priority = 5 AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_last_name_same_court_active_period_unique_gender'
            WHEN ha.html_best_match_priority = 6 AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_last_name_same_court_unique_gender'
            WHEN ha.html_best_match_priority = 7 AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_last_name_any_court_active_period_unique_gender'
            WHEN ha.html_best_match_priority = 8 AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_last_name_any_court_unique_gender'
            WHEN ha.html_best_match_priority = 9 AND ha.html_n_candidate_judges = 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_compound_last_same_court_unique_judge'
            WHEN ha.html_best_match_priority = 9 AND ha.html_n_candidate_judges > 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_compound_last_same_court_unique_gender'
            WHEN ha.html_best_match_priority IN (10,11) AND ha.html_n_candidate_judges = 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_suffix_stripped_same_court_unique_judge'
            WHEN ha.html_best_match_priority IN (10,11) AND ha.html_n_candidate_judges > 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_judge_suffix_stripped_same_court_unique_gender'
            WHEN COALESCE(ha.html_n_candidate_judges, 0) > 0
             AND COALESCE(ha.html_n_candidate_genders, 0) > 1
                THEN 'html_judge_ambiguous_multiple_genders'
            WHEN COALESCE(ha.html_n_candidate_judges, 0) > 0
             AND COALESCE(ha.html_n_candidate_genders, 0) = 0
                THEN 'html_judge_candidates_without_gender'
            WHEN ha.html_extracted_author_name IS NOT NULL
                THEN 'html_no_judge_match'
            ELSE NULL
        END AS html_gender_source,

        CASE
            WHEN ha.html_best_match_priority = 1 AND ha.html_n_candidate_judges = 1
             AND ha.html_n_candidate_genders = 1  THEN 5
            WHEN ha.html_best_match_priority = 1 AND ha.html_n_candidate_judges > 1
             AND ha.html_n_candidate_genders = 1  THEN 6
            WHEN ha.html_best_match_priority = 2 AND ha.html_n_candidate_genders = 1  THEN 7
            WHEN ha.html_best_match_priority = 3 AND ha.html_n_candidate_genders = 1  THEN 8
            WHEN ha.html_best_match_priority = 4 AND ha.html_n_candidate_genders = 1  THEN 9
            WHEN ha.html_best_match_priority = 5 AND ha.html_n_candidate_genders = 1  THEN 11
            WHEN ha.html_best_match_priority = 6 AND ha.html_n_candidate_genders = 1  THEN 12
            WHEN ha.html_best_match_priority = 7 AND ha.html_n_candidate_genders = 1  THEN 16
            WHEN ha.html_best_match_priority = 8 AND ha.html_n_candidate_genders = 1  THEN 17
            WHEN ha.html_best_match_priority = 9 AND ha.html_n_candidate_genders = 1  THEN 13
            WHEN ha.html_best_match_priority = 10 AND ha.html_n_candidate_genders = 1 THEN 14
            WHEN ha.html_best_match_priority = 11 AND ha.html_n_candidate_genders = 1 THEN 15
            WHEN COALESCE(ha.html_n_candidate_judges, 0) > 0
             AND COALESCE(ha.html_n_candidate_genders, 0) > 1  THEN 90
            WHEN COALESCE(ha.html_n_candidate_judges, 0) > 0
             AND COALESCE(ha.html_n_candidate_genders, 0) = 0  THEN 91
            ELSE 99
        END AS html_gender_match_quality_tier,

        CASE
            WHEN ha.html_best_match_priority = 1 AND ha.html_n_candidate_judges = 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_exact_full_name_same_court_unique_judge'
            WHEN ha.html_best_match_priority = 1 AND ha.html_n_candidate_judges > 1
             AND ha.html_n_candidate_genders = 1
                THEN 'html_exact_full_name_same_court_unique_gender'
            WHEN ha.html_best_match_priority = 2 AND ha.html_n_candidate_genders = 1
                THEN 'html_initials_last_name_same_court_unique_gender'
            WHEN ha.html_best_match_priority = 3 AND ha.html_n_candidate_genders = 1
                THEN 'html_exact_full_name_any_court_unique_gender'
            WHEN ha.html_best_match_priority = 4 AND ha.html_n_candidate_genders = 1
                THEN 'html_initials_last_name_any_court_unique_gender'
            WHEN ha.html_best_match_priority = 5 AND ha.html_n_candidate_genders = 1
                THEN 'html_last_name_same_court_active_period_unique_gender'
            WHEN ha.html_best_match_priority = 6 AND ha.html_n_candidate_genders = 1
                THEN 'html_last_name_same_court_unique_gender'
            WHEN ha.html_best_match_priority = 7 AND ha.html_n_candidate_genders = 1
                THEN 'html_last_name_any_court_active_period_unique_gender'
            WHEN ha.html_best_match_priority = 8 AND ha.html_n_candidate_genders = 1
                THEN 'html_last_name_any_court_unique_gender'
            WHEN ha.html_best_match_priority = 9 AND ha.html_n_candidate_genders = 1
                THEN 'html_compound_last_same_court_unique_gender'
            WHEN ha.html_best_match_priority IN (10,11) AND ha.html_n_candidate_genders = 1
                THEN 'html_suffix_stripped_same_court_unique_gender'
            WHEN COALESCE(ha.html_n_candidate_judges, 0) > 0
             AND COALESCE(ha.html_n_candidate_genders, 0) > 1
                THEN 'html_ambiguous_multiple_genders'
            WHEN COALESCE(ha.html_n_candidate_judges, 0) > 0
             AND COALESCE(ha.html_n_candidate_genders, 0) = 0
                THEN 'html_candidates_without_gender'
            ELSE 'html_no_judge_match'
        END AS html_gender_match_quality_label

    FROM base b
    LEFT JOIN xml_aggregated  xa ON xa.opinion_id = b.opinion_id
    LEFT JOIN html_aggregated ha ON ha.opinion_id = b.opinion_id
)

SELECT * FROM result;

-- --------------------------------------------------------
-- Indexes
-- --------------------------------------------------------
ALTER TABLE ext.author_gender_from_text_extraction
ADD PRIMARY KEY (opinion_id);

CREATE INDEX idx_text_ext_xml_gender_resolved
    ON ext.author_gender_from_text_extraction(xml_gender_resolved);

CREATE INDEX idx_text_ext_html_gender_resolved
    ON ext.author_gender_from_text_extraction(html_gender_resolved);

CREATE INDEX idx_text_ext_court_id
    ON ext.author_gender_from_text_extraction(court_id);

CREATE INDEX idx_text_ext_year_filed
    ON ext.author_gender_from_text_extraction(year_filed);

CREATE INDEX idx_text_ext_opinion_type
    ON ext.author_gender_from_text_extraction(opinion_type);

CREATE INDEX idx_text_ext_html_type
    ON ext.author_gender_from_text_extraction(html_type);

CREATE INDEX idx_text_ext_html_extraction_pattern
    ON ext.author_gender_from_text_extraction(html_extraction_pattern);

ANALYZE ext.author_gender_from_text_extraction;

COMMIT;
