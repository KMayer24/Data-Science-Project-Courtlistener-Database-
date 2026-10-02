-- ============================================================
-- 01_select_federal_appeals_corpus.sql
--
-- Purpose:
--   Define the court universe for the analysis.
--
--   The analysis is restricted to the 13 modern United States
--   federal courts of appeals:
--
--     ca1, ca2, ca3, ca4, ca5, ca6, ca7,
--     ca8, ca9, ca10, ca11, cadc, cafc
--
--   This script does not modify the original CourtListener tables.
--   It creates documentation tables in the ext schema only.
--
-- Note on court selection:
--   Courts are selected by explicit ID rather than by name or
--   jurisdiction flag because many state, tribal, military,
--   territorial, and specialised courts also contain the phrase
--   "Court of Appeals" in their name, and the jurisdiction flag
--   'F' includes historical federal courts outside the target set.
-- ============================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS ext;

-- ------------------------------------------------------------
-- 1. Included court universe
-- ------------------------------------------------------------

DROP TABLE IF EXISTS ext.federal_appeal_courts;

CREATE TABLE ext.federal_appeal_courts AS
SELECT
    id,
    short_name,
    full_name,
    jurisdiction,
    CASE
        WHEN id IN ('ca1','ca2','ca3','ca4','ca5','ca6','ca7',
                    'ca8','ca9','ca10','ca11','cadc','cafc')
        THEN 'included: modern U.S. federal court of appeals'
    END AS inclusion_reason
FROM public.search_court
WHERE id IN (
    'ca1','ca2','ca3','ca4','ca5','ca6','ca7',
    'ca8','ca9','ca10','ca11','cadc','cafc'
);

ALTER TABLE ext.federal_appeal_courts
ADD PRIMARY KEY (id);

COMMENT ON TABLE ext.federal_appeal_courts IS
'The 13 modern U.S. federal courts of appeals used as the analysis court universe.';


-- ------------------------------------------------------------
-- 2. Excluded courts that also contain "Court of Appeals"
-- ------------------------------------------------------------

DROP TABLE IF EXISTS ext.excluded_appeals_named_courts;

CREATE TABLE ext.excluded_appeals_named_courts AS
SELECT
    id,
    short_name,
    full_name,
    jurisdiction,
    CASE
        WHEN jurisdiction IN ('SA', 'S', 'ST') THEN 'state_court'
        WHEN jurisdiction = 'TRA' THEN 'tribal_court'
        WHEN jurisdiction = 'TA' THEN 'territorial_court'
        WHEN jurisdiction = 'MA' THEN 'military_court'
        WHEN jurisdiction = 'FS' THEN 'specialized_federal_court'
        WHEN jurisdiction = 'F' THEN 'historical_or_non_target_federal_court'
        ELSE 'other_non_target_court'
    END AS exclusion_category,
    'Excluded because it is not one of the 13 modern U.S. federal courts of appeals.' AS exclusion_reason
FROM public.search_court
WHERE full_name ILIKE '%Court of Appeals%'
  AND id NOT IN (
      'ca1','ca2','ca3','ca4','ca5','ca6','ca7',
      'ca8','ca9','ca10','ca11','cadc','cafc'
  );

COMMENT ON TABLE ext.excluded_appeals_named_courts IS
'Courts with Court of Appeals in the name that are excluded from the federal appeals analysis.';


-- ------------------------------------------------------------
-- 3. Sanity check: exactly 13 courts should be included
-- ------------------------------------------------------------

DO $$
DECLARE
    n_courts integer;
BEGIN
    SELECT COUNT(*) INTO n_courts
    FROM ext.federal_appeal_courts;

    IF n_courts <> 13 THEN
        RAISE EXCEPTION 'Expected 13 federal appeal courts, found %', n_courts;
    END IF;
END $$;

COMMIT;