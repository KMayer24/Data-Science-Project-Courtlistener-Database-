-- ============================================================
-- 11_inspect_unmatched_author_str_fjc.sql
--
-- Purpose:
--   Inspect author_str-FJC cases that were not matched in the
--   conservative exact-name matching step.
--
-- Focus:
--   - frequent no_fjc_match author_str values
--   - possible suffix matches against FJC last names
--   - possible accent / spelling issues
--
-- Input:
--   ext.author_gender_author_str_fjc
--   ext.fjc_judge_bio
--   ext.fjc_judge_court
--   ext.fjc_court_name_map
--
-- Notes:
--   This script does not create or modify tables.
--   It is only diagnostic.
-- ============================================================

\pset pager off
\timing on


-- ------------------------------------------------------------
-- 1. Most frequent no-FJC-match author_str values
-- ------------------------------------------------------------

SELECT
    court_id,
    court_short_name,
    author_str,
    author_last_name_norm,
    COUNT(*) AS n_opinions
FROM ext.author_gender_author_str_fjc
WHERE gender_source = 'no_fjc_match'
GROUP BY
    court_id,
    court_short_name,
    author_str,
    author_last_name_norm
ORDER BY n_opinions DESC
LIMIT 100;


-- ------------------------------------------------------------
-- 2. Build FJC Appeals judge name universe with same normalization
-- ------------------------------------------------------------

WITH fjc_appeals_judges AS (
    SELECT DISTINCT
        m.court_id,
        jc.court_name,
        b.nid,
        b.jid,
        b.first_name,
        b.middle_name,
        b.last_name,

        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(b.last_name, ''),
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
        ) AS fjc_last_name_norm,

        -- Last token of the normalized FJC surname.
        -- This helps diagnose cases like:
        --   Orsdel      -> Van Orsdel
        --   Graafeiland -> Van Graafeiland
        --   Oosterhout  -> Van Oosterhout
        --   Dusen       -> Van Dusen
        (
            REGEXP_MATCH(
                LOWER(
                    TRIM(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    COALESCE(b.last_name, ''),
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
                ),
                '([^ ]+)$'
            )
        )[1] AS fjc_last_name_final_token,

        b.gender,
        b.race_or_ethnicity

    FROM ext.fjc_judge_court jc
    JOIN ext.fjc_judge_bio b
        ON jc.nid = b.nid
    JOIN ext.fjc_court_name_map m
        ON jc.court_name = m.fjc_court_name
    WHERE jc.court_type = 'U.S. Court of Appeals'
      AND b.gender IN ('m', 'f')
      AND b.last_name IS NOT NULL
      AND TRIM(b.last_name) <> ''
),

unmatched_names AS (
    SELECT
        court_id,
        court_short_name,
        author_str,
        author_last_name_norm,
        COUNT(*) AS n_opinions
    FROM ext.author_gender_author_str_fjc
    WHERE gender_source = 'no_fjc_match'
    GROUP BY
        court_id,
        court_short_name,
        author_str,
        author_last_name_norm
),

possible_suffix_matches AS (
    SELECT
        u.court_id,
        u.court_short_name,
        u.author_str,
        u.author_last_name_norm,
        u.n_opinions,

        f.nid,
        f.jid,
        f.first_name,
        f.middle_name,
        f.last_name,
        f.fjc_last_name_norm,
        f.fjc_last_name_final_token,
        f.gender

    FROM unmatched_names u
    JOIN fjc_appeals_judges f
        ON u.court_id = f.court_id
       AND u.author_last_name_norm = f.fjc_last_name_final_token
       AND u.author_last_name_norm <> f.fjc_last_name_norm
)

SELECT
    court_id,
    court_short_name,
    author_str,
    author_last_name_norm,
    n_opinions,

    COUNT(DISTINCT nid) AS n_suffix_candidate_judges,
    COUNT(DISTINCT gender) AS n_suffix_candidate_genders,

    STRING_AGG(
        DISTINCT CONCAT_WS(' ', first_name, middle_name, last_name),
        '; '
        ORDER BY CONCAT_WS(' ', first_name, middle_name, last_name)
    ) AS suffix_candidate_names,

    STRING_AGG(
        DISTINCT gender,
        '; '
        ORDER BY gender
    ) AS suffix_candidate_genders

FROM possible_suffix_matches
GROUP BY
    court_id,
    court_short_name,
    author_str,
    author_last_name_norm,
    n_opinions
ORDER BY n_opinions DESC
LIMIT 100;


-- ------------------------------------------------------------
-- 3. Summary: how many no_fjc_match opinions could be resolved
--    by conservative suffix matching?
-- ------------------------------------------------------------

WITH fjc_appeals_judges AS (
    SELECT DISTINCT
        m.court_id,
        b.nid,

        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(b.last_name, ''),
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
        ) AS fjc_last_name_norm,

        (
            REGEXP_MATCH(
                LOWER(
                    TRIM(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    COALESCE(b.last_name, ''),
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
                ),
                '([^ ]+)$'
            )
        )[1] AS fjc_last_name_final_token,

        b.gender

    FROM ext.fjc_judge_court jc
    JOIN ext.fjc_judge_bio b
        ON jc.nid = b.nid
    JOIN ext.fjc_court_name_map m
        ON jc.court_name = m.fjc_court_name
    WHERE jc.court_type = 'U.S. Court of Appeals'
      AND b.gender IN ('m', 'f')
      AND b.last_name IS NOT NULL
      AND TRIM(b.last_name) <> ''
),

candidate_suffix_matches AS (
    SELECT
        ags.opinion_id,
        COUNT(DISTINCT f.nid) AS n_suffix_candidate_judges,
        COUNT(DISTINCT f.gender) AS n_suffix_candidate_genders,
        MIN(f.gender) AS suffix_resolved_gender
    FROM ext.author_gender_author_str_fjc ags
    JOIN fjc_appeals_judges f
        ON ags.court_id = f.court_id
       AND ags.author_last_name_norm = f.fjc_last_name_final_token
       AND ags.author_last_name_norm <> f.fjc_last_name_norm
    WHERE ags.gender_source = 'no_fjc_match'
    GROUP BY ags.opinion_id
)

SELECT
    COUNT(*) AS n_no_fjc_match_with_suffix_candidate,

    COUNT(*) FILTER (
        WHERE n_suffix_candidate_genders = 1
    ) AS n_resolvable_by_suffix_gender_unique,

    COUNT(*) FILTER (
        WHERE n_suffix_candidate_genders > 1
    ) AS n_still_ambiguous_by_suffix,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE n_suffix_candidate_genders = 1
        ) / NULLIF(
            (SELECT COUNT(*)
             FROM ext.author_gender_author_str_fjc
             WHERE gender_source = 'no_fjc_match'),
            0
        ),
        2
    ) AS pct_of_no_fjc_match_resolvable_by_suffix,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE n_suffix_candidate_genders = 1
        ) / NULLIF(
            (SELECT COUNT(*)
             FROM ext.federal_appeal_opinions),
            0
        ),
        2
    ) AS pct_of_all_opinions_resolvable_by_suffix

FROM candidate_suffix_matches;


-- ------------------------------------------------------------
-- 4. Potential suffix resolution by court
-- ------------------------------------------------------------

WITH fjc_appeals_judges AS (
    SELECT DISTINCT
        m.court_id,

        b.nid,

        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(b.last_name, ''),
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
        ) AS fjc_last_name_norm,

        (
            REGEXP_MATCH(
                LOWER(
                    TRIM(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    COALESCE(b.last_name, ''),
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
                ),
                '([^ ]+)$'
            )
        )[1] AS fjc_last_name_final_token,

        b.gender

    FROM ext.fjc_judge_court jc
    JOIN ext.fjc_judge_bio b
        ON jc.nid = b.nid
    JOIN ext.fjc_court_name_map m
        ON jc.court_name = m.fjc_court_name
    WHERE jc.court_type = 'U.S. Court of Appeals'
      AND b.gender IN ('m', 'f')
      AND b.last_name IS NOT NULL
      AND TRIM(b.last_name) <> ''
),

candidate_suffix_matches AS (
    SELECT
        ags.opinion_id,
        ags.court_id,
        ags.court_short_name,
        COUNT(DISTINCT f.nid) AS n_suffix_candidate_judges,
        COUNT(DISTINCT f.gender) AS n_suffix_candidate_genders
    FROM ext.author_gender_author_str_fjc ags
    JOIN fjc_appeals_judges f
        ON ags.court_id = f.court_id
       AND ags.author_last_name_norm = f.fjc_last_name_final_token
       AND ags.author_last_name_norm <> f.fjc_last_name_norm
    WHERE ags.gender_source = 'no_fjc_match'
    GROUP BY
        ags.opinion_id,
        ags.court_id,
        ags.court_short_name
)

SELECT
    court_id,
    court_short_name,
    COUNT(*) AS n_no_fjc_match_with_suffix_candidate,

    COUNT(*) FILTER (
        WHERE n_suffix_candidate_genders = 1
    ) AS n_resolvable_by_suffix_gender_unique,

    COUNT(*) FILTER (
        WHERE n_suffix_candidate_genders > 1
    ) AS n_still_ambiguous_by_suffix

FROM candidate_suffix_matches
GROUP BY court_id, court_short_name
ORDER BY court_id;


-- ------------------------------------------------------------
-- 5. Exact inspection for selected frequent no-match names
-- ------------------------------------------------------------

WITH fjc_appeals_judges AS (
    SELECT DISTINCT
        m.court_id,
        jc.court_name,
        b.nid,
        b.jid,
        b.first_name,
        b.middle_name,
        b.last_name,

        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(b.last_name, ''),
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
        ) AS fjc_last_name_norm,

        (
            REGEXP_MATCH(
                LOWER(
                    TRIM(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    COALESCE(b.last_name, ''),
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
                ),
                '([^ ]+)$'
            )
        )[1] AS fjc_last_name_final_token,

        b.gender,
        b.race_or_ethnicity

    FROM ext.fjc_judge_court jc
    JOIN ext.fjc_judge_bio b
        ON jc.nid = b.nid
    JOIN ext.fjc_court_name_map m
        ON jc.court_name = m.fjc_court_name
    WHERE jc.court_type = 'U.S. Court of Appeals'
      AND b.gender IN ('m', 'f')
      AND b.last_name IS NOT NULL
      AND TRIM(b.last_name) <> ''
)

SELECT
    u.court_id,
    u.court_short_name,
    u.author_str,
    u.author_last_name_norm,

    f.nid,
    f.jid,
    f.first_name,
    f.middle_name,
    f.last_name,
    f.fjc_last_name_norm,
    f.fjc_last_name_final_token,
    f.gender

FROM (
    SELECT DISTINCT
        court_id,
        court_short_name,
        author_str,
        author_last_name_norm
    FROM ext.author_gender_author_str_fjc
    WHERE gender_source = 'no_fjc_match'
      AND author_last_name_norm IN (
          'orsdel',
          'alarcon',
          'scannlain',
          'de brorby',
          'graafeiland',
          'oosterhout',
          'dusen',
          'mcfadden',
          'kollarkotelly'
      )
) u
LEFT JOIN fjc_appeals_judges f
    ON u.court_id = f.court_id
   AND (
        u.author_last_name_norm = f.fjc_last_name_norm
        OR u.author_last_name_norm = f.fjc_last_name_final_token
   )
ORDER BY
    u.court_id,
    u.author_last_name_norm,
    f.last_name;

\pset pager off
\timing on


-- ------------------------------------------------------------
-- 1. Most frequent no-FJC-match author_str values
-- ------------------------------------------------------------

SELECT
    court_id,
    court_short_name,
    author_str,
    author_last_name_norm,
    COUNT(*) AS n_opinions
FROM ext.author_gender_author_str_fjc
WHERE gender_source = 'no_fjc_match'
GROUP BY
    court_id,
    court_short_name,
    author_str,
    author_last_name_norm
ORDER BY n_opinions DESC
LIMIT 100;


-- ------------------------------------------------------------
-- 2. Build FJC Appeals judge name universe with same normalization
-- ------------------------------------------------------------

WITH fjc_appeals_judges AS (
    SELECT DISTINCT
        m.court_id,
        jc.court_name,
        b.nid,
        b.jid,
        b.first_name,
        b.middle_name,
        b.last_name,

        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(b.last_name, ''),
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
        ) AS fjc_last_name_norm,

        -- Last token of the normalized FJC surname.
        -- This helps diagnose cases like:
        --   Orsdel      -> Van Orsdel
        --   Graafeiland -> Van Graafeiland
        --   Oosterhout  -> Van Oosterhout
        --   Dusen       -> Van Dusen
        (
            REGEXP_MATCH(
                LOWER(
                    TRIM(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    COALESCE(b.last_name, ''),
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
                ),
                '([^ ]+)$'
            )
        )[1] AS fjc_last_name_final_token,

        b.gender,
        b.race_or_ethnicity

    FROM ext.fjc_judge_court jc
    JOIN ext.fjc_judge_bio b
        ON jc.nid = b.nid
    JOIN ext.fjc_court_name_map m
        ON jc.court_name = m.fjc_court_name
    WHERE jc.court_type = 'U.S. Court of Appeals'
      AND b.gender IN ('m', 'f')
      AND b.last_name IS NOT NULL
      AND TRIM(b.last_name) <> ''
),

unmatched_names AS (
    SELECT
        court_id,
        court_short_name,
        author_str,
        author_last_name_norm,
        COUNT(*) AS n_opinions
    FROM ext.author_gender_author_str_fjc
    WHERE gender_source = 'no_fjc_match'
    GROUP BY
        court_id,
        court_short_name,
        author_str,
        author_last_name_norm
),

possible_suffix_matches AS (
    SELECT
        u.court_id,
        u.court_short_name,
        u.author_str,
        u.author_last_name_norm,
        u.n_opinions,

        f.nid,
        f.jid,
        f.first_name,
        f.middle_name,
        f.last_name,
        f.fjc_last_name_norm,
        f.fjc_last_name_final_token,
        f.gender

    FROM unmatched_names u
    JOIN fjc_appeals_judges f
        ON u.court_id = f.court_id
       AND u.author_last_name_norm = f.fjc_last_name_final_token
       AND u.author_last_name_norm <> f.fjc_last_name_norm
)

SELECT
    court_id,
    court_short_name,
    author_str,
    author_last_name_norm,
    n_opinions,

    COUNT(DISTINCT nid) AS n_suffix_candidate_judges,
    COUNT(DISTINCT gender) AS n_suffix_candidate_genders,

    STRING_AGG(
        DISTINCT CONCAT_WS(' ', first_name, middle_name, last_name),
        '; '
        ORDER BY CONCAT_WS(' ', first_name, middle_name, last_name)
    ) AS suffix_candidate_names,

    STRING_AGG(
        DISTINCT gender,
        '; '
        ORDER BY gender
    ) AS suffix_candidate_genders

FROM possible_suffix_matches
GROUP BY
    court_id,
    court_short_name,
    author_str,
    author_last_name_norm,
    n_opinions
ORDER BY n_opinions DESC
LIMIT 100;


-- ------------------------------------------------------------
-- 3. Summary: how many no_fjc_match opinions could be resolved
--    by conservative suffix matching?
-- ------------------------------------------------------------

WITH fjc_appeals_judges AS (
    SELECT DISTINCT
        m.court_id,
        b.nid,

        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(b.last_name, ''),
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
        ) AS fjc_last_name_norm,

        (
            REGEXP_MATCH(
                LOWER(
                    TRIM(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    COALESCE(b.last_name, ''),
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
                ),
                '([^ ]+)$'
            )
        )[1] AS fjc_last_name_final_token,

        b.gender

    FROM ext.fjc_judge_court jc
    JOIN ext.fjc_judge_bio b
        ON jc.nid = b.nid
    JOIN ext.fjc_court_name_map m
        ON jc.court_name = m.fjc_court_name
    WHERE jc.court_type = 'U.S. Court of Appeals'
      AND b.gender IN ('m', 'f')
      AND b.last_name IS NOT NULL
      AND TRIM(b.last_name) <> ''
),

candidate_suffix_matches AS (
    SELECT
        ags.opinion_id,
        COUNT(DISTINCT f.nid) AS n_suffix_candidate_judges,
        COUNT(DISTINCT f.gender) AS n_suffix_candidate_genders,
        MIN(f.gender) AS suffix_resolved_gender
    FROM ext.author_gender_author_str_fjc ags
    JOIN fjc_appeals_judges f
        ON ags.court_id = f.court_id
       AND ags.author_last_name_norm = f.fjc_last_name_final_token
       AND ags.author_last_name_norm <> f.fjc_last_name_norm
    WHERE ags.gender_source = 'no_fjc_match'
    GROUP BY ags.opinion_id
)

SELECT
    COUNT(*) AS n_no_fjc_match_with_suffix_candidate,

    COUNT(*) FILTER (
        WHERE n_suffix_candidate_genders = 1
    ) AS n_resolvable_by_suffix_gender_unique,

    COUNT(*) FILTER (
        WHERE n_suffix_candidate_genders > 1
    ) AS n_still_ambiguous_by_suffix,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE n_suffix_candidate_genders = 1
        ) / NULLIF(
            (SELECT COUNT(*)
             FROM ext.author_gender_author_str_fjc
             WHERE gender_source = 'no_fjc_match'),
            0
        ),
        2
    ) AS pct_of_no_fjc_match_resolvable_by_suffix,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE n_suffix_candidate_genders = 1
        ) / NULLIF(
            (SELECT COUNT(*)
             FROM ext.federal_appeal_opinions),
            0
        ),
        2
    ) AS pct_of_all_opinions_resolvable_by_suffix

FROM candidate_suffix_matches;


-- ------------------------------------------------------------
-- 4. Potential suffix resolution by court
-- ------------------------------------------------------------

WITH fjc_appeals_judges AS (
    SELECT DISTINCT
        m.court_id,

        b.nid,

        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(b.last_name, ''),
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
        ) AS fjc_last_name_norm,

        (
            REGEXP_MATCH(
                LOWER(
                    TRIM(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    COALESCE(b.last_name, ''),
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
                ),
                '([^ ]+)$'
            )
        )[1] AS fjc_last_name_final_token,

        b.gender

    FROM ext.fjc_judge_court jc
    JOIN ext.fjc_judge_bio b
        ON jc.nid = b.nid
    JOIN ext.fjc_court_name_map m
        ON jc.court_name = m.fjc_court_name
    WHERE jc.court_type = 'U.S. Court of Appeals'
      AND b.gender IN ('m', 'f')
      AND b.last_name IS NOT NULL
      AND TRIM(b.last_name) <> ''
),

candidate_suffix_matches AS (
    SELECT
        ags.opinion_id,
        ags.court_id,
        ags.court_short_name,
        COUNT(DISTINCT f.nid) AS n_suffix_candidate_judges,
        COUNT(DISTINCT f.gender) AS n_suffix_candidate_genders
    FROM ext.author_gender_author_str_fjc ags
    JOIN fjc_appeals_judges f
        ON ags.court_id = f.court_id
       AND ags.author_last_name_norm = f.fjc_last_name_final_token
       AND ags.author_last_name_norm <> f.fjc_last_name_norm
    WHERE ags.gender_source = 'no_fjc_match'
    GROUP BY
        ags.opinion_id,
        ags.court_id,
        ags.court_short_name
)

SELECT
    court_id,
    court_short_name,
    COUNT(*) AS n_no_fjc_match_with_suffix_candidate,

    COUNT(*) FILTER (
        WHERE n_suffix_candidate_genders = 1
    ) AS n_resolvable_by_suffix_gender_unique,

    COUNT(*) FILTER (
        WHERE n_suffix_candidate_genders > 1
    ) AS n_still_ambiguous_by_suffix

FROM candidate_suffix_matches
GROUP BY court_id, court_short_name
ORDER BY court_id;


-- ------------------------------------------------------------
-- 5. Exact inspection for selected frequent no-match names
-- ------------------------------------------------------------

WITH fjc_appeals_judges AS (
    SELECT DISTINCT
        m.court_id,
        jc.court_name,
        b.nid,
        b.jid,
        b.first_name,
        b.middle_name,
        b.last_name,

        LOWER(
            TRIM(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        REGEXP_REPLACE(
                            COALESCE(b.last_name, ''),
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
        ) AS fjc_last_name_norm,

        (
            REGEXP_MATCH(
                LOWER(
                    TRIM(
                        REGEXP_REPLACE(
                            REGEXP_REPLACE(
                                REGEXP_REPLACE(
                                    COALESCE(b.last_name, ''),
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
                ),
                '([^ ]+)$'
            )
        )[1] AS fjc_last_name_final_token,

        b.gender,
        b.race_or_ethnicity

    FROM ext.fjc_judge_court jc
    JOIN ext.fjc_judge_bio b
        ON jc.nid = b.nid
    JOIN ext.fjc_court_name_map m
        ON jc.court_name = m.fjc_court_name
    WHERE jc.court_type = 'U.S. Court of Appeals'
      AND b.gender IN ('m', 'f')
      AND b.last_name IS NOT NULL
      AND TRIM(b.last_name) <> ''
)

SELECT
    u.court_id,
    u.court_short_name,
    u.author_str,
    u.author_last_name_norm,

    f.nid,
    f.jid,
    f.first_name,
    f.middle_name,
    f.last_name,
    f.fjc_last_name_norm,
    f.fjc_last_name_final_token,
    f.gender

FROM (
    SELECT DISTINCT
        court_id,
        court_short_name,
        author_str,
        author_last_name_norm
    FROM ext.author_gender_author_str_fjc
    WHERE gender_source = 'no_fjc_match'
      AND author_last_name_norm IN (
          'orsdel',
          'alarcon',
          'scannlain',
          'de brorby',
          'graafeiland',
          'oosterhout',
          'dusen',
          'mcfadden',
          'kollarkotelly'
      )
) u
LEFT JOIN fjc_appeals_judges f
    ON u.court_id = f.court_id
   AND (
        u.author_last_name_norm = f.fjc_last_name_norm
        OR u.author_last_name_norm = f.fjc_last_name_final_token
   )
ORDER BY
    u.court_id,
    u.author_last_name_norm,
    f.last_name;