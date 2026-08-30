DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

BEGIN;

CREATE TABLE public.search_court (
    id varchar(15) PRIMARY KEY,
    pacer_court_id smallint,
    pacer_has_rss_feed boolean,
    pacer_rss_entry_types text,
    date_last_pacer_contact timestamptz,
    fjc_court_id varchar(3),
    date_modified timestamptz,
    in_use boolean,
    has_opinion_scraper boolean,
    has_oral_argument_scraper boolean,
    "position" double precision,
    citation_string varchar(100),
    short_name varchar(100),
    full_name varchar(200),
    url varchar(500),
    start_date date,
    end_date date,
    jurisdiction varchar(3),
    notes text,
    parent_court_id varchar(15),
    CONSTRAINT search_court_pacer_court_id_check
        CHECK (pacer_court_id IS NULL OR pacer_court_id >= 0)
);

CREATE TABLE public.recap_fjcintegrateddatabase (
    id integer PRIMARY KEY,
    date_created timestamptz,
    date_modified timestamptz,
    dataset_source smallint,
    office varchar(3),
    docket_number varchar(100),
    origin smallint,
    date_filed date,
    jurisdiction smallint,
    nature_of_suit smallint,
    title varchar(500),
    section varchar(500),
    subsection varchar(500),
    diversity_of_residence smallint,
    class_action boolean,
    monetary_demand varchar(100),
    county_of_residence varchar(100),
    arbitration_at_filing varchar(10),
    arbitration_at_termination varchar(10),
    multidistrict_litigation_docket_number varchar(100),
    plaintiff varchar(500),
    defendant varchar(500),
    date_transfer date,
    transfer_office varchar(3),
    transfer_docket_number varchar(100),
    transfer_origin varchar(3),
    date_terminated date,
    termination_class_action_status smallint,
    procedural_progress smallint,
    disposition smallint,
    nature_of_judgement smallint,
    amount_received integer,
    judgment smallint,
    pro_se smallint,
    year_of_tape smallint,
    nature_of_offense smallint,
    version smallint,
    circuit_id varchar(15),
    district_id varchar(15),
    CONSTRAINT fk_fjcidb_circuit
        FOREIGN KEY (circuit_id)
        REFERENCES public.search_court(id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_fjcidb_district
        FOREIGN KEY (district_id)
        REFERENCES public.search_court(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.people_db_person (
    id integer PRIMARY KEY,
    date_created timestamptz,
    date_modified timestamptz,
    date_completed timestamptz,
    fjc_id integer,
    slug varchar(158),
    name_first varchar(50),
    name_middle varchar(50),
    name_last varchar(50),
    name_suffix varchar(5),
    date_dob date,
    date_granularity_dob varchar(15),
    date_dod date,
    date_granularity_dod varchar(15),
    dob_city varchar(50),
    dob_state varchar(2),
    dob_country varchar(50),
    dod_city varchar(50),
    dod_state varchar(2),
    dod_country varchar(50),
    gender varchar(2),
    religion varchar(30),
    ftm_total_received double precision,
    ftm_eid varchar(30),
    has_photo boolean,
    is_alias_of_id integer
);

CREATE TABLE public.people_db_race (
    id integer PRIMARY KEY,
    race varchar(5)
);

CREATE TABLE public.people_db_person_race (
    id integer PRIMARY KEY,
    person_id integer,
    race_id integer,
    CONSTRAINT fk_personrace_person
        FOREIGN KEY (person_id)
        REFERENCES public.people_db_person(id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_personrace_race
        FOREIGN KEY (race_id)
        REFERENCES public.people_db_race(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.people_db_school (
    id integer PRIMARY KEY,
    date_created timestamptz,
    date_modified timestamptz,
    name varchar(120),
    ein integer,
    is_alias_of_id integer
);

CREATE TABLE public.people_db_position (
    id integer PRIMARY KEY,
    date_created timestamptz,
    date_modified timestamptz,
    position_type varchar(20),
    job_title varchar(100),
    sector smallint,
    organization_name varchar(120),
    location_city varchar(50),
    location_state varchar(2),
    date_nominated date,
    date_elected date,
    date_recess_appointment date,
    date_referred_to_judicial_committee date,
    date_judicial_committee_action date,
    judicial_committee_action varchar(20),
    date_hearing date,
    date_confirmation date,
    date_start date,
    date_granularity_start varchar(15),
    date_termination date,
    termination_reason varchar(25),
    date_granularity_termination varchar(15),
    date_retirement date,
    nomination_process varchar(20),
    vote_type varchar(2),
    voice_vote boolean,
    votes_yes integer,
    votes_no integer,
    votes_yes_percent double precision,
    votes_no_percent double precision,
    how_selected varchar(20),
    has_inferred_values boolean,
    appointer_id integer,
    court_id varchar(15),
    person_id integer,
    predecessor_id integer,
    school_id integer,
    supervisor_id integer,
    CONSTRAINT people_db_position_votes_no_check
        CHECK (votes_no IS NULL OR votes_no >= 0),
    CONSTRAINT people_db_position_votes_yes_check
        CHECK (votes_yes IS NULL OR votes_yes >= 0),
    CONSTRAINT fk_position_person
        FOREIGN KEY (person_id)
        REFERENCES public.people_db_person(id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_position_court
        FOREIGN KEY (court_id)
        REFERENCES public.search_court(id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_position_school
        FOREIGN KEY (school_id)
        REFERENCES public.people_db_school(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.people_db_politicalaffiliation (
    id integer PRIMARY KEY,
    date_created timestamptz,
    date_modified timestamptz,
    political_party varchar(5),
    source varchar(5),
    date_start date,
    date_granularity_start varchar(15),
    date_end date,
    date_granularity_end varchar(15),
    person_id integer,
    CONSTRAINT fk_polaffil_person
        FOREIGN KEY (person_id)
        REFERENCES public.people_db_person(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.people_db_education (
    id integer PRIMARY KEY,
    date_created timestamptz,
    date_modified timestamptz,
    degree_level varchar(4),
    degree_detail varchar(100),
    degree_year smallint,
    person_id integer,
    school_id integer,
    CONSTRAINT fk_education_person
        FOREIGN KEY (person_id)
        REFERENCES public.people_db_person(id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_education_school
        FOREIGN KEY (school_id)
        REFERENCES public.people_db_school(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.search_docket (
    id integer PRIMARY KEY,
    date_created timestamptz,
    date_modified timestamptz,
    source smallint,
    appeal_from_str text,
    assigned_to_str text,
    referred_to_str text,
    panel_str text,
    date_last_index timestamptz,
    date_cert_granted date,
    date_cert_denied date,
    date_argued date,
    date_reargued date,
    date_reargument_denied date,
    date_filed date,
    date_terminated date,
    date_last_filing date,
    case_name_short text,
    case_name text,
    case_name_full text,
    slug varchar(75),
    docket_number text,
    docket_number_core varchar(20),
    pacer_case_id varchar(100),
    cause varchar(2000),
    nature_of_suit varchar(1000),
    jury_demand varchar(500),
    jurisdiction_type varchar(100),
    appellate_fee_status text,
    appellate_case_type_information text,
    mdl_status varchar(100),
    filepath_local varchar(1000),
    filepath_ia varchar(1000),
    filepath_ia_json varchar(1000),
    ia_upload_failure_count smallint,
    ia_needs_upload boolean,
    ia_date_first_change timestamptz,
    view_count integer,
    date_blocked date,
    blocked boolean,
    appeal_from_id varchar(15),
    assigned_to_id integer,
    court_id varchar(15),
    idb_data_id integer,
    originating_court_information_id integer,
    referred_to_id integer,
    federal_dn_case_type varchar(6),
    federal_dn_office_code varchar(3),
    federal_dn_judge_initials_assigned varchar(5),
    federal_dn_judge_initials_referred varchar(5),
    federal_defendant_number smallint,
    parent_docket_id integer,
    docket_number_raw varchar,
    docket_number_source smallint DEFAULT 0,
    CONSTRAINT search_docket_docket_number_source_check
        CHECK (docket_number_source IS NULL OR docket_number_source >= 0),
    CONSTRAINT fk_docket_court
        FOREIGN KEY (court_id)
        REFERENCES public.search_court(id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_docket_idb_data
        FOREIGN KEY (idb_data_id)
        REFERENCES public.recap_fjcintegrateddatabase(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.search_opinioncluster (
    id integer PRIMARY KEY,
    date_created timestamptz,
    date_modified timestamptz,
    judges text,
    date_filed date,
    date_filed_is_approximate boolean,
    slug varchar(75),
    case_name_short text,
    case_name text,
    case_name_full text,
    scdb_id varchar(10),
    scdb_decision_direction integer,
    scdb_votes_majority integer,
    scdb_votes_minority integer,
    source varchar(10),
    procedural_history text,
    attorneys text,
    nature_of_suit text,
    posture text,
    syllabus text,
    headnotes text,
    summary text,
    disposition text,
    history text,
    other_dates text,
    cross_reference text,
    correction text,
    citation_count integer,
    precedential_status varchar(50),
    date_blocked date,
    blocked boolean,
    filepath_json_harvard varchar(1000),
    filepath_pdf_harvard varchar(100),
    filepath_pdf_scan varchar(100),
    filepath_xml_scan varchar(100),
    docket_id integer,
    arguments text,
    headmatter text,
    CONSTRAINT fk_cluster_docket
        FOREIGN KEY (docket_id)
        REFERENCES public.search_docket(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.search_opinion (
    id integer PRIMARY KEY,
    date_created timestamptz,
    date_modified timestamptz,
    author_str text,
    per_curiam boolean,
    joined_by_str text,
    type varchar(20),
    sha1 varchar(40),
    page_count integer,
    download_url varchar(500),
    local_path varchar(100),
    plain_text text,
    html text,
    html_lawbox text,
    html_columbia text,
    html_anon_2020 text,
    xml_harvard text,
    xml_scan text,
    html_with_citations text,
    extracted_by_ocr boolean,
    author_id integer,
    cluster_id integer,
    ordering_key integer,
    main_version_id integer,
    CONSTRAINT fk_opinion_cluster
        FOREIGN KEY (cluster_id)
        REFERENCES public.search_opinioncluster(id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_opinion_author
        FOREIGN KEY (author_id)
        REFERENCES public.people_db_person(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.search_opinioncluster_panel (
    id integer PRIMARY KEY,
    opinioncluster_id integer,
    person_id integer,
    CONSTRAINT fk_panel_cluster
        FOREIGN KEY (opinioncluster_id)
        REFERENCES public.search_opinioncluster(id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_panel_person
        FOREIGN KEY (person_id)
        REFERENCES public.people_db_person(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.search_opinion_joined_by (
    id integer PRIMARY KEY,
    opinion_id integer,
    person_id integer,
    CONSTRAINT fk_joinedby_opinion
        FOREIGN KEY (opinion_id)
        REFERENCES public.search_opinion(id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_joinedby_person
        FOREIGN KEY (person_id)
        REFERENCES public.people_db_person(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.search_opinioncluster_non_participating_judges (
    id integer PRIMARY KEY,
    opinioncluster_id integer,
    person_id integer,
    CONSTRAINT fk_nonpart_cluster
        FOREIGN KEY (opinioncluster_id)
        REFERENCES public.search_opinioncluster(id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_nonpart_person
        FOREIGN KEY (person_id)
        REFERENCES public.people_db_person(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.search_opinionscited (
    id integer PRIMARY KEY,
    depth integer,
    cited_opinion_id integer,
    citing_opinion_id integer,
    CONSTRAINT fk_opinionscited_cited
        FOREIGN KEY (cited_opinion_id)
        REFERENCES public.search_opinion(id)
        DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_opinionscited_citing
        FOREIGN KEY (citing_opinion_id)
        REFERENCES public.search_opinion(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE public.search_citation (
    id integer PRIMARY KEY,
    volume integer,
    reporter varchar(50),
    page varchar(50),
    type varchar(50),
    cluster_id integer,
    date_created timestamptz,
    date_modified timestamptz,
    CONSTRAINT fk_citation_cluster
        FOREIGN KEY (cluster_id)
        REFERENCES public.search_opinioncluster(id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX idx_cluster_docket       ON public.search_opinioncluster(docket_id);
CREATE INDEX idx_cluster_date         ON public.search_opinioncluster(date_filed);
CREATE INDEX idx_opinion_cluster      ON public.search_opinion(cluster_id);
CREATE INDEX idx_opinion_author       ON public.search_opinion(author_id);
CREATE INDEX idx_court_jurisdiction   ON public.search_court(jurisdiction);
CREATE INDEX idx_panel_cluster        ON public.search_opinioncluster_panel(opinioncluster_id);
CREATE INDEX idx_panel_person         ON public.search_opinioncluster_panel(person_id);
CREATE INDEX idx_position_person      ON public.people_db_position(person_id);
CREATE INDEX idx_position_court       ON public.people_db_position(court_id);
CREATE INDEX idx_polaffil_person      ON public.people_db_politicalaffiliation(person_id);
CREATE INDEX idx_docket_court         ON public.search_docket(court_id);
CREATE INDEX idx_education_person     ON public.people_db_education(person_id);
CREATE INDEX idx_education_school     ON public.people_db_education(school_id);
CREATE INDEX idx_opinionscited_cited  ON public.search_opinionscited(cited_opinion_id);
CREATE INDEX idx_opinionscited_citing ON public.search_opinionscited(citing_opinion_id);
CREATE INDEX idx_citation_cluster     ON public.search_citation(cluster_id);

-- Index supporting later FJC IDB joins.
CREATE INDEX IF NOT EXISTS idx_fjc_docket_district
    ON public.recap_fjcintegrateddatabase (docket_number, district_id, year_of_tape DESC NULLS LAST)
    WHERE district_id IS NOT NULL AND docket_number IS NOT NULL;

COMMIT;
