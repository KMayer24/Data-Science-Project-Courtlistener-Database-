/*
===============================================================================
20_fjc_code_crosswalks.sql   (v2 -- populated from the official IDB codebooks)
===============================================================================

Now sourced from:
  Appeals_Codebook_1971-2007.pdf         (fields + values)
  Appeals_Codebook_2008_Forward.pdf      (Appendix A NOS, Appendix B offense)

Routing principle (codebook, "Purpose and Limitations"): read ONLY the detail
field that matches the appeal's Type of Appeal (APPTYPE). That routing lives in
script 21. Here we only provide the code -> label / code -> rq2_domain lookups.

RQ2 domain taxonomy (must equal NB30): criminal, immigration, civil_rights,
employment, benefits, other.

Judgment calls are marked  [CALL]  -- change the rq2_domain there if you want a
different convention; they are defensible either way and documented for the thesis.
===============================================================================
*/

\pset pager off
\timing on

BEGIN;

-- ---------------------------------------------------------------------------
-- A. OUTCOME (the result). Codebook OUTCOME, SY85+ values (post-1984).
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ext.fjc_outcome_crosswalk;
CREATE TABLE ext.fjc_outcome_crosswalk (
    outcome_code  text PRIMARY KEY,
    outcome_label text NOT NULL,
    outcome_class text NOT NULL       -- affirmed | reversed | mixed | other | missing
);
INSERT INTO ext.fjc_outcome_crosswalk VALUES
    ('1','affirmed_enforced',                 'affirmed'),
    ('2','reversed_vacated',                   'reversed'),
    ('3','affirmed_in_part_reversed_in_part',  'mixed'),
    ('5','dismissed',                          'other'),
    ('6','remanded',                           'reversed'),
    ('7','other_merits',                       'other'),
    ('9','certificate_of_appealability_denied','other'),
    ('-8','missing',                           'missing');
-- Pre-SY85 note: code 4 = "Dismissed - Want of Jurisdiction" existed SY71-84
-- and 7 = "Transferred". They fall through to 'other' via the default in 21.

-- ---------------------------------------------------------------------------
-- B. DISPOSITION (procedural mode; SY85+). NOT a result.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ext.fjc_disposition_crosswalk;
CREATE TABLE ext.fjc_disposition_crosswalk (
    disposition_code  text PRIMARY KEY,
    disposition_label text NOT NULL
);
INSERT INTO ext.fjc_disposition_crosswalk VALUES
    ('1','merits_after_oral_hearing'),
    ('2','merits_after_submission_no_hearing'),
    ('3','merits_after_submission_court_rule'),
    ('4','procedural_after_other_judicial_action'),
    ('5','procedural_without_judicial_action'),
    ('-8','missing');

-- ---------------------------------------------------------------------------
-- C. DOMAIN. code_kind in ('nature_of_suit','agency'). Offense-immigration and
--    the criminal default are handled by rule in script 21 (range 8710-8750).
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS ext.fjc_domain_crosswalk;
CREATE TABLE ext.fjc_domain_crosswalk (
    code_kind  text NOT NULL,          -- 'nature_of_suit' | 'agency'
    code_value text NOT NULL,
    rq2_domain text NOT NULL,
    note       text,
    PRIMARY KEY (code_kind, code_value)
);

-- ---- Nature of Suit (Appendix A), only the non-'other' domains -------------
INSERT INTO ext.fjc_domain_crosswalk (code_kind, code_value, rq2_domain, note) VALUES
    -- immigration
    ('nature_of_suit','460','immigration','DEPORTATION'),
    -- civil rights
    ('nature_of_suit','440','civil_rights','OTHER CIVIL RIGHTS'),
    ('nature_of_suit','441','civil_rights','VOTING'),
    ('nature_of_suit','443','civil_rights','ACCOMMODATIONS'),
    ('nature_of_suit','444','civil_rights','WELFARE'),
    ('nature_of_suit','550','civil_rights','PRISONER - CIVIL RIGHTS'),
    ('nature_of_suit','555','civil_rights','PRISONER - PRISON CONDITION'),
    ('nature_of_suit','442','employment','CIVIL RIGHTS JOBS = employment discrim [CALL: could be civil_rights]'),
    -- employment / labor
    ('nature_of_suit','710','employment','FAIR LABOR STANDARDS ACT'),
    ('nature_of_suit','720','employment','LABOR/MANAGEMENT RELATIONS'),
    ('nature_of_suit','730','employment','LABOR/MGMT REPORT & DISCLOSURE'),
    ('nature_of_suit','740','employment','RAILWAY LABOR ACT'),
    ('nature_of_suit','790','employment','OTHER LABOR LITIGATION'),
    ('nature_of_suit','791','employment','ERISA [CALL: benefits-adjacent]'),
    -- benefits (social security family + related)
    ('nature_of_suit','860','benefits','SOCIAL SECURITY'),
    ('nature_of_suit','861','benefits','MEDICARE'),
    ('nature_of_suit','862','benefits','BLACK LUNG'),
    ('nature_of_suit','863','benefits','DIWC/DIWW'),
    ('nature_of_suit','864','benefits','SSID'),
    ('nature_of_suit','865','benefits','RSI'),
    ('nature_of_suit','153','benefits','RECOVERY OVERPAYMENT VET BENEFITS [CALL: could be other]');
    -- NOTE: prisoner habeas 510/530/535/540 deliberately NOT mapped -> fall to
    -- 'other'. They are criminal in substance but civil in form; folding them
    -- into 'criminal' would inflate it with a different population than the RQ2
    -- direct-criminal-appeal scenarios. [CALL] revisit if you want a habeas bucket.

-- ---- Administrative agency (APPTYPE 1/2), non-'other' domains --------------
-- Codebook agency values: numeric 6 = INS, plus text codes. Immigration also
-- appears as 'DHS' post-2003. Employment = labor/employment boards.
INSERT INTO ext.fjc_domain_crosswalk (code_kind, code_value, rq2_domain, note) VALUES
    ('agency','6',   'immigration','INS (numeric)'),
    ('agency','INS', 'immigration','INS'),
    ('agency','DHS', 'immigration','Dept of Homeland Security'),
    ('agency','1',   'employment','NLRB (numeric)'),
    ('agency','EEOC','employment','Equal Employment Opportunity Commission'),
    ('agency','FLRA','employment','Federal Labor Relations Authority'),
    ('agency','FLRB','employment','Federal Labor Relations Authority'),
    ('agency','MSPB','employment','Merit Systems Protection Board'),
    ('agency','LABR','employment','Department of Labor'),
    ('agency','OSHR','employment','OSHA Review Commission [CALL]'),
    ('agency','OSHC','employment','OSHA Review Commission [CALL]'),
    ('agency','SSA', 'benefits','Social Security Administration'),
    ('agency','BRB', 'benefits','Benefits Review Board'),
    ('agency','OWCP','benefits','Office of Workers Compensation [CALL: employment?]'),
    ('agency','DVA', 'benefits','Dept of Veterans Affairs'),
    ('agency','VET', 'benefits','Veterans Administration');
    -- Immigration caveat: petitions for review whose respondent is coded under
    -- DOJ/EOIR rather than INS/DHS will NOT be caught here. Check the agency
    -- enumeration for a large DOJ block before trusting immigration counts.

COMMIT;


/*
===============================================================================
Helper enumerations (jurisdiction-free; use appeal_type_code as the router).
Run to confirm coverage before trusting the crosswalk.
===============================================================================
*/

-- Appeal-type distribution: the top-level router. Verify these are populated.
SELECT appeal_type_code, count(*) AS n
FROM ext.fjc_opinion_match
WHERE match_eligible
GROUP BY appeal_type_code ORDER BY n DESC;

-- Agency distribution among administrative appeals (APPTYPE 1/2) -- watch for a
-- big DOJ/EOIR block that would be missed immigration.
SELECT agency_code, count(*) AS n
FROM ext.fjc_opinion_match
WHERE match_eligible AND appeal_type_code IN ('1','2')
GROUP BY agency_code ORDER BY n DESC LIMIT 40;

-- NOS not covered by the crosswalk, among civil appeals -> these become 'other'.
SELECT m.nature_of_suit_code, count(*) AS n
FROM ext.fjc_opinion_match m
LEFT JOIN ext.fjc_domain_crosswalk x
       ON x.code_kind = 'nature_of_suit' AND x.code_value = m.nature_of_suit_code
WHERE m.match_eligible AND m.appeal_type_code IN ('3','4','7') AND x.code_value IS NULL
GROUP BY m.nature_of_suit_code ORDER BY n DESC LIMIT 40;
