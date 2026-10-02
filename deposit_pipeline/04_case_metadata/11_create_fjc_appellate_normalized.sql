/*
===============================================================================
11_create_fjc_appellate_normalized.sql
===============================================================================
-- The 2008+ source does not contain the historical OTHTYPE column.

-- A typed NULL placeholder is used to preserve a consistent UNION schema.

Purpose
-------
Create one standardized appellate FJC table from the two imported raw files:

    ext.fjc_appellate_raw_1971to2007
    ext.fjc_appellate_raw_2008plus

The preserved snapshots can be restored with:

    tools/import_fjc_appellate_raw.sh

The table harmonizes the FJC circuit codes with the CourtListener court IDs.
It is intended as the clean input table for the later FJC-to-CourtListener
matching procedure.

Court-code crosswalk
--------------------
    FJC 0  -> CourtListener cadc
    FJC 1  -> CourtListener ca1
    FJC 2  -> CourtListener ca2
    FJC 3  -> CourtListener ca3
    FJC 4  -> CourtListener ca4
    FJC 5  -> CourtListener ca5
    FJC 6  -> CourtListener ca6
    FJC 7  -> CourtListener ca7
    FJC 8  -> CourtListener ca8
    FJC 9  -> CourtListener ca9
    FJC 10 -> CourtListener ca10
    FJC 11 -> CourtListener ca11

Notes
-----
1. The Federal Circuit (cafc) is not represented by a separate circuit code in
   the two imported FJC appellate files.
2. A duplicated CSV header row with circuit = 'CIRCUIT' is excluded.
3. Raw values are retained as text. Dates and docket numbers will be normalized
   separately before record linkage so that the raw source values remain
   available for validation.
4. Only fields shared by both raw tables and relevant for the later matching
   and outcome analysis are selected here.
5. fjc_appeal_id is assigned from a total ordering of all normalized fields.
   The first five fields alone contain duplicate sort keys, so using only
   those fields makes ROW_NUMBER dependent on executor/worker order.

Output
------
    ext.fjc_appellate_normalized

===============================================================================
*/

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.fjc_appellate_normalized;

CREATE TABLE ext.fjc_appellate_normalized AS
WITH combined AS (
    SELECT
        '1971to2007'::text AS source_period,
        circuit,
        docket,
        reopen,
        dktdate,
        appellan,
        appellee,
        apptype,
        agency,
        juris,
        nos,
        offense,
        othtype,
        disp,
        outcome,
        judgdate,
        opinion,
        tapeyear
    FROM ext.fjc_appellate_raw_1971to2007

    UNION ALL

    SELECT
        '2008plus'::text AS source_period,
        circuit,
        docket,
        reopen,
        dktdate,
        appellan,
        appellee,
        apptype,
        agency,
        juris,
        nos,
        offense,
        NULL::text AS othtype,
        disp,
        outcome,
        judgdate,
        opinion,
        tapeyear
    FROM ext.fjc_appellate_raw_2008plus
),
cleaned AS (
    SELECT
        source_period,
        NULLIF(BTRIM(circuit), '') AS fjc_circuit_code,
        NULLIF(BTRIM(docket), '') AS fjc_docket_raw,
        NULLIF(BTRIM(reopen), '') AS reopen_code,
        NULLIF(BTRIM(dktdate), '') AS docket_date_raw,
        NULLIF(BTRIM(appellan), '') AS appellant,
        NULLIF(BTRIM(appellee), '') AS appellee,
        NULLIF(BTRIM(apptype), '') AS appeal_type_code,
        NULLIF(BTRIM(agency), '') AS agency_code,
        NULLIF(BTRIM(juris), '') AS jurisdiction_code,
        NULLIF(BTRIM(nos), '') AS nature_of_suit_code,
        NULLIF(BTRIM(offense), '') AS offense_code,
        NULLIF(BTRIM(othtype), '') AS other_type_code,
        NULLIF(BTRIM(disp), '') AS disposition_code,
        NULLIF(BTRIM(outcome), '') AS outcome_code,
        NULLIF(BTRIM(judgdate), '') AS judgment_date_raw,
        NULLIF(BTRIM(opinion), '') AS opinion_code,
        NULLIF(BTRIM(tapeyear), '') AS tape_year_raw
    FROM combined
    WHERE UPPER(BTRIM(circuit)) <> 'CIRCUIT'
)
SELECT
    ROW_NUMBER() OVER (
        ORDER BY source_period, fjc_circuit_code, fjc_docket_raw,
                 docket_date_raw, judgment_date_raw,
                 reopen_code, appellant, appellee, appeal_type_code,
                 agency_code, jurisdiction_code, nature_of_suit_code,
                 offense_code, other_type_code, disposition_code,
                 outcome_code, opinion_code, tape_year_raw
    )::bigint AS fjc_appeal_id,

    source_period,

    CASE fjc_circuit_code
        WHEN '0'  THEN 'cadc'
        WHEN '1'  THEN 'ca1'
        WHEN '2'  THEN 'ca2'
        WHEN '3'  THEN 'ca3'
        WHEN '4'  THEN 'ca4'
        WHEN '5'  THEN 'ca5'
        WHEN '6'  THEN 'ca6'
        WHEN '7'  THEN 'ca7'
        WHEN '8'  THEN 'ca8'
        WHEN '9'  THEN 'ca9'
        WHEN '10' THEN 'ca10'
        WHEN '11' THEN 'ca11'
        ELSE NULL
    END AS court_id,

    fjc_circuit_code,
    fjc_docket_raw,
    reopen_code,
    docket_date_raw,
    judgment_date_raw,
    appellant,
    appellee,
    appeal_type_code,
    agency_code,
    jurisdiction_code,
    nature_of_suit_code,
    offense_code,
    other_type_code,
    disposition_code,
    outcome_code,
    opinion_code,
    tape_year_raw
FROM cleaned
WHERE fjc_circuit_code IN (
    '0', '1', '2', '3', '4', '5',
    '6', '7', '8', '9', '10', '11'
);

ALTER TABLE ext.fjc_appellate_normalized
    ADD CONSTRAINT fjc_appellate_normalized_pkey
    PRIMARY KEY (fjc_appeal_id);

CREATE INDEX idx_fjc_appellate_normalized_court_id
    ON ext.fjc_appellate_normalized (court_id);

CREATE INDEX idx_fjc_appellate_normalized_docket_raw
    ON ext.fjc_appellate_normalized (fjc_docket_raw);

CREATE INDEX idx_fjc_appellate_normalized_court_docket
    ON ext.fjc_appellate_normalized (court_id, fjc_docket_raw);

CREATE INDEX idx_fjc_appellate_normalized_judgment_date_raw
    ON ext.fjc_appellate_normalized (judgment_date_raw);

CREATE INDEX idx_fjc_appellate_normalized_source_period
    ON ext.fjc_appellate_normalized (source_period);

ANALYZE ext.fjc_appellate_normalized;

COMMIT;


/*
===============================================================================
Validation
===============================================================================
*/

-- 1. Overall row count and source-period coverage.
SELECT
    COUNT(*) AS n_rows,
    COUNT(*) FILTER (WHERE source_period = '1971to2007') AS n_1971to2007,
    COUNT(*) FILTER (WHERE source_period = '2008plus') AS n_2008plus
FROM ext.fjc_appellate_normalized;


-- 2. Confirm the FJC-to-CourtListener court-code crosswalk.
SELECT
    fjc_circuit_code,
    court_id,
    COUNT(*) AS n_rows
FROM ext.fjc_appellate_normalized
GROUP BY fjc_circuit_code, court_id
ORDER BY fjc_circuit_code::integer;


-- 3. Confirm that every retained row received a CourtListener court ID.
SELECT
    COUNT(*) AS n_missing_court_id
FROM ext.fjc_appellate_normalized
WHERE court_id IS NULL;


-- 4. Check key matching-field coverage by court.
SELECT
    court_id,
    COUNT(*) AS n_rows,
    COUNT(fjc_docket_raw) AS n_with_docket,
    COUNT(docket_date_raw) AS n_with_docket_date,
    COUNT(judgment_date_raw) AS n_with_judgment_date,
    COUNT(appellant) AS n_with_appellant,
    COUNT(appellee) AS n_with_appellee
FROM ext.fjc_appellate_normalized
GROUP BY court_id
ORDER BY court_id;


-- 5. Identify unexpected circuit values excluded from the normalized table.
SELECT
    source_table,
    circuit,
    COUNT(*) AS n_rows
FROM (
    SELECT
        '1971to2007'::text AS source_table,
        circuit
    FROM ext.fjc_appellate_raw_1971to2007

    UNION ALL

    SELECT
        '2008plus'::text AS source_table,
        circuit
    FROM ext.fjc_appellate_raw_2008plus
) x
WHERE UPPER(BTRIM(circuit)) <> 'CIRCUIT'
  AND BTRIM(circuit) NOT IN (
      '0', '1', '2', '3', '4', '5',
      '6', '7', '8', '9', '10', '11'
  )
GROUP BY source_table, circuit
ORDER BY source_table, circuit;
