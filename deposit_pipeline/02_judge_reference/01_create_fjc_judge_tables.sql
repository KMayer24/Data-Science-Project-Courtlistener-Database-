-- ============================================================
-- 01_create_fjc_judge_tables.sql
--
-- Purpose:
--   Load Federal Judicial Center judge data into ext.* for
--   author-gender matching in Step~2 and Steps~3--4.
--
-- Inputs:
--   data/processed/fjc_judges/fjc_judge_bio.csv
--   data/processed/fjc_judges/fjc_judge_court.csv
--
-- Output:
--   ext.fjc_judge_bio      Judge-level demographics including gender.
--   ext.fjc_judge_court    Court-service records per judge.
--
-- Note:
--   nid is used as the primary join key between the two files.
--   jid links to the CourtListener fjc_id field on people_db_person.
--
-- Prerequisite:
--   None. This script is independent of the corpus selection scripts.
--
-- Run before:
--   02_validate_fjc_judge_tables.sql
--   03_create_fjc_court_name_map.sql
-- ============================================================

\pset pager off
\timing on

BEGIN;

CREATE SCHEMA IF NOT EXISTS ext;

DROP TABLE IF EXISTS ext.fjc_judge_court;
DROP TABLE IF EXISTS ext.fjc_judge_bio;

CREATE TABLE ext.fjc_judge_bio (
    nid integer PRIMARY KEY,
    jid integer,
    last_name text,
    first_name text,
    middle_name text,
    suffix text,
    gender varchar(1),
    race_or_ethnicity text
);

CREATE TABLE ext.fjc_judge_court (
    id serial PRIMARY KEY,
    nid integer NOT NULL,
    appointment_seq integer,
    judge_name text,
    court_type text,
    court_name text,
    appointment_title text,
    appointing_president text,
    party_of_appointing_president text,
    commission_date date,
    termination text,
    termination_date date,
    CONSTRAINT fk_fjc_judge_court_bio
        FOREIGN KEY (nid)
        REFERENCES ext.fjc_judge_bio(nid)
);

\COPY ext.fjc_judge_bio (nid, jid, last_name, first_name, middle_name, suffix, gender, race_or_ethnicity) FROM 'data/processed/fjc_judges/fjc_judge_bio.csv' WITH (FORMAT csv, HEADER, ENCODING 'UTF8');

\COPY ext.fjc_judge_court (nid, appointment_seq, judge_name, court_type, court_name, appointment_title, appointing_president, party_of_appointing_president, commission_date, termination, termination_date) FROM 'data/processed/fjc_judges/fjc_judge_court.csv' WITH (FORMAT csv, HEADER, ENCODING 'UTF8');

COMMIT;

CREATE INDEX IF NOT EXISTS idx_fjc_judge_bio_jid
    ON ext.fjc_judge_bio(jid);

CREATE INDEX IF NOT EXISTS idx_fjc_judge_bio_last_name
    ON ext.fjc_judge_bio(LOWER(last_name));

CREATE INDEX IF NOT EXISTS idx_fjc_judge_bio_gender
    ON ext.fjc_judge_bio(gender);

CREATE INDEX IF NOT EXISTS idx_fjc_judge_court_nid
    ON ext.fjc_judge_court(nid);

CREATE INDEX IF NOT EXISTS idx_fjc_judge_court_type
    ON ext.fjc_judge_court(court_type);

CREATE INDEX IF NOT EXISTS idx_fjc_judge_court_name
    ON ext.fjc_judge_court(court_name);

CREATE INDEX IF NOT EXISTS idx_fjc_judge_court_type_name
    ON ext.fjc_judge_court(court_type, court_name);
