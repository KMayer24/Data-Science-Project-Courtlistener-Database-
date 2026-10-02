
/*
18_audit_fjc_duplicate_dockets.sql

Purpose:
- Check how often FJC docket numbers are duplicated.
- Never deduplicate only by docket number.
- Treat fjc_appeal_id as the FJC row identifier.
*/

\pset pager off
\timing on

WITH fjc AS (
    SELECT
        fjc_appeal_id,
        court_id,
        lpad(fjc_docket_raw, 7, '0') AS normalized_docket,
        fjc_docket_raw,
        source_period,
        disposition_code,
        outcome_code,
        CASE
            WHEN judgment_date_raw ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            THEN to_date(judgment_date_raw, 'MM/DD/YYYY')
        END AS judgment_date
    FROM ext.fjc_appellate_normalized
    WHERE court_id IN (
        'ca1','ca2','ca3','ca4','ca5','ca6',
        'ca7','ca8','ca9','ca10','ca11','cadc'
    )
)
SELECT
    court_id,
    normalized_docket,
    count(*) AS n_fjc_rows,
    count(DISTINCT judgment_date) AS n_distinct_judgment_dates,
    count(DISTINCT outcome_code) AS n_distinct_outcomes,
    min(judgment_date) AS first_judgment_date,
    max(judgment_date) AS last_judgment_date,
    string_agg(
        fjc_appeal_id::text || ':' ||
        coalesce(to_char(judgment_date, 'YYYY-MM-DD'), 'NULL') || ':' ||
        coalesce(outcome_code::text, 'NULL'),
        ', ' ORDER BY judgment_date, fjc_appeal_id
    ) AS fjc_rows
FROM fjc
GROUP BY court_id, normalized_docket
HAVING count(*) > 1
ORDER BY n_fjc_rows DESC, court_id, normalized_docket;


/*
Summary of duplicate prevalence.
*/

WITH fjc AS (
    SELECT
        fjc_appeal_id,
        court_id,
        lpad(fjc_docket_raw, 7, '0') AS normalized_docket
    FROM ext.fjc_appellate_normalized
    WHERE court_id IN (
        'ca1','ca2','ca3','ca4','ca5','ca6',
        'ca7','ca8','ca9','ca10','ca11','cadc'
    )
),
groups AS (
    SELECT
        court_id,
        normalized_docket,
        count(*) AS n_rows
    FROM fjc
    GROUP BY court_id, normalized_docket
)
SELECT
    count(*) AS n_court_docket_groups,
    count(*) FILTER (WHERE n_rows = 1) AS n_unique_groups,
    count(*) FILTER (WHERE n_rows > 1) AS n_duplicate_groups,
    sum(n_rows) FILTER (WHERE n_rows > 1) AS n_rows_in_duplicate_groups,
    max(n_rows) AS max_rows_per_court_docket
FROM groups;
