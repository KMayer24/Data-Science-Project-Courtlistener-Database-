/*
===============================================================================
21_materialize_opinion_covariates.sql   (v3 -- APPTYPE-based codebook router)
===============================================================================

Routing (codebook "Purpose and Limitations"): the appeal's Type of Appeal
determines which detail field carries the case type. Read only that field.

  APPTYPE 5,8,13-21  criminal      -> offense  (8710-8750 -> immigration)
  APPTYPE 1,2        administrative-> agency   (INS/DHS -> immigration, ...)
  APPTYPE 3,4,7      civil         -> nature_of_suit
  APPTYPE 6          original proceeding -> other
  APPTYPE 9-12       bankruptcy    -> other
  APPTYPE 22 / else  misc          -> other

Feeds:
  (A) language:  projection_score ~ author_gender + decade + circuit + rq2_domain
  (B) outcome:   outcome_class    ~ author_gender + decade + circuit + rq2_domain
outcome_class is the DV of (B); NEVER a control in (A) (post-treatment).

Prereq: 19 (v2, carries agency_code) and 20 (v2) have been run.
===============================================================================
*/

\pset pager off
\timing on

BEGIN;

DROP TABLE IF EXISTS ext.opinion_fjc_covariates;

CREATE TABLE ext.opinion_fjc_covariates AS
WITH base AS (
    SELECT
        m.*,
        CASE
            WHEN m.appeal_type_code IN ('3','4','7')                     THEN 'civil'
            WHEN m.appeal_type_code IN ('5','8','13','14','15','16','17',
                                        '18','19','20','21')             THEN 'criminal'
            WHEN m.appeal_type_code IN ('1','2')                         THEN 'administrative'
            WHEN m.appeal_type_code = '6'                                THEN 'original_proceeding'
            WHEN m.appeal_type_code IN ('9','10','11','12')              THEN 'bankruptcy'
            ELSE 'other'
        END AS case_class
    FROM ext.fjc_opinion_match m
    WHERE m.match_tier NOT IN ('not_parseable', 'no_fjc_match')
)
SELECT
    b.opinion_id,
    b.cluster_id,
    b.court_id,
    b.opinion_date,
    date_part('year', b.opinion_date)::int                    AS year_filed,
    (floor(date_part('year', b.opinion_date) / 10) * 10)::int AS decade,

    b.match_tier,
    b.date_diff_days,
    b.was_ambiguous,
    b.fjc_appeal_id,

    b.case_class,
    (b.case_class = 'civil')                                  AS is_civil,

    -- rq2_domain via the APPTYPE router (reads only the matching detail field)
    CASE
        WHEN b.case_class = 'criminal' THEN
            CASE WHEN b.offense_code IN ('8710','8720','8730','8740','8750')
                 THEN 'immigration' ELSE 'criminal' END
        WHEN b.case_class = 'administrative' THEN COALESCE(ag.rq2_domain, 'other')
        WHEN b.case_class = 'civil'          THEN COALESCE(nos.rq2_domain, 'other')
        ELSE 'other'
    END                                                       AS rq2_domain,

    b.appeal_type_code,
    b.nature_of_suit_code,
    b.offense_code,
    b.agency_code,
    b.jurisdiction_code,

    -- RESULT (DV for regression B)
    b.outcome_code,
    COALESCE(oc.outcome_label, 'unmapped')                    AS outcome_label,
    COALESCE(oc.outcome_class, 'other')                       AS outcome_class,

    -- PROCEDURAL mode (descriptive only; NOT a result)
    b.disposition_code,
    COALESCE(dc.disposition_label, 'unmapped')                AS disposition_label,

    b.match_eligible                                          AS analysis_eligible
FROM base b
LEFT JOIN ext.fjc_outcome_crosswalk     oc  ON oc.outcome_code = b.outcome_code
LEFT JOIN ext.fjc_disposition_crosswalk dc  ON dc.disposition_code = b.disposition_code
LEFT JOIN ext.fjc_domain_crosswalk      nos ON nos.code_kind = 'nature_of_suit'
                                           AND nos.code_value = b.nature_of_suit_code
LEFT JOIN ext.fjc_domain_crosswalk      ag  ON ag.code_kind = 'agency'
                                           AND ag.code_value = b.agency_code;

ALTER TABLE ext.opinion_fjc_covariates
    ADD CONSTRAINT opinion_fjc_covariates_pkey PRIMARY KEY (opinion_id);

CREATE INDEX idx_ofc_eligible ON ext.opinion_fjc_covariates (analysis_eligible);
CREATE INDEX idx_ofc_domain   ON ext.opinion_fjc_covariates (rq2_domain);
CREATE INDEX idx_ofc_outcome  ON ext.opinion_fjc_covariates (outcome_class);
CREATE INDEX idx_ofc_class    ON ext.opinion_fjc_covariates (case_class);

ANALYZE ext.opinion_fjc_covariates;

COMMIT;


/*
===============================================================================
Validation
===============================================================================
*/

-- 1. case_class split (expect civil / criminal / administrative / ... , NOT all one bucket).
SELECT case_class, count(*) AS n
FROM ext.opinion_fjc_covariates
WHERE analysis_eligible
GROUP BY case_class ORDER BY n DESC;

-- 2. RQ2 domain distribution -- the payoff. Compare shares to NB30's domain mix
--    (criminal 66, immigration 19, other 17, civil_rights 11, employment 9, benefits 4).
SELECT rq2_domain, count(*) AS n,
       round(100.0*count(*)/sum(count(*)) OVER (),1) AS pct
FROM ext.opinion_fjc_covariates
WHERE analysis_eligible
GROUP BY rq2_domain ORDER BY n DESC;

-- 3. Outcome distribution; 'unmapped' should be tiny.
SELECT outcome_class, outcome_label, count(*) AS n
FROM ext.opinion_fjc_covariates
WHERE analysis_eligible
GROUP BY outcome_class, outcome_label ORDER BY n DESC;

-- 4. Cross-check: immigration by source (criminal-offense vs agency vs NOS).
SELECT case_class, count(*) AS n
FROM ext.opinion_fjc_covariates
WHERE analysis_eligible AND rq2_domain = 'immigration'
GROUP BY case_class ORDER BY n DESC;
