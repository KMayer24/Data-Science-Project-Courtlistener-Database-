#!/bin/bash
set -e

DB_NAME="${BULK_DB_NAME:-courtcase_db}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE="${BULK_DIR:-$SCRIPT_DIR}"
PSQL_OPTS="${BULK_DB_HOST:+--host $BULK_DB_HOST} ${BULK_DB_USER:+--username $BULK_DB_USER}"
export PGPASSWORD="${BULK_DB_PASSWORD:-}"

# Apply schema if requested
if [[ "${APPLY_SCHEMA:-0}" == "1" ]]; then
    echo "Applying schema_final.sql..."
    psql $PSQL_OPTS -d "$DB_NAME" -f "$BASE/schema_final.sql"
fi

echo "Loading search_court..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.search_court (
  id, pacer_court_id, pacer_has_rss_feed, pacer_rss_entry_types, date_last_pacer_contact,
  fjc_court_id, date_modified, in_use, has_opinion_scraper,
  has_oral_argument_scraper, position, citation_string, short_name, full_name,
  url, start_date, end_date, jurisdiction, notes, parent_court_id
) FROM '$BASE/courts-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading people_db_person..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.people_db_person (
  id, date_created, date_modified, date_completed, fjc_id, slug, name_first,
  name_middle, name_last, name_suffix, date_dob, date_granularity_dob,
  date_dod, date_granularity_dod, dob_city, dob_state, dob_country,
  dod_city, dod_state, dod_country, gender, religion, ftm_total_received,
  ftm_eid, has_photo, is_alias_of_id
) FROM '$BASE/people-db-people-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading people_db_race..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.people_db_race (
  id, race
) FROM '$BASE/people_db_race-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading people_db_person_race..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.people_db_person_race (
  id, person_id, race_id
) FROM '$BASE/people-db-races-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading people_db_school..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.people_db_school (
  id, date_created, date_modified, name, ein, is_alias_of_id
) FROM '$BASE/people-db-schools-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading people_db_position..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.people_db_position (
  id, date_created, date_modified, position_type, job_title,
  sector, organization_name, location_city, location_state,
  date_nominated, date_elected, date_recess_appointment,
  date_referred_to_judicial_committee, date_judicial_committee_action,
  judicial_committee_action, date_hearing, date_confirmation, date_start,
  date_granularity_start, date_termination, termination_reason,
  date_granularity_termination, date_retirement, nomination_process, vote_type,
  voice_vote, votes_yes, votes_no, votes_yes_percent, votes_no_percent, how_selected,
  has_inferred_values, appointer_id, court_id, person_id, predecessor_id, school_id,
  supervisor_id
) FROM '$BASE/people-db-positions-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading people_db_politicalaffiliation..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.people_db_politicalaffiliation (
  id, date_created, date_modified, political_party, source,
  date_start, date_granularity_start, date_end, date_granularity_end, person_id
) FROM '$BASE/people-db-political-affiliations-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading people_db_education..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.people_db_education (
  id, date_created, date_modified, degree_level, degree_detail,
  degree_year, person_id, school_id
) FROM '$BASE/people-db-educations-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading recap_fjcintegrateddatabase..."
# The .bz2 file uses quoted empty strings ("") and backslash escaping.
# Pipe through Python csv to normalise → unquoted empty fields = NULL in PG.
FJC_FILE="$BASE/fjc-integrated-database-2026-03-31.csv"
if [[ -f "${FJC_FILE}.bz2" && ! -f "$FJC_FILE" ]]; then
    CAT_CMD="bzcat ${FJC_FILE}.bz2"
else
    CAT_CMD="cat $FJC_FILE"
fi
eval "$CAT_CMD" \
  | python3 -c "
import csv, sys
r = csv.reader(sys.stdin, escapechar='\\\\')
w = csv.writer(sys.stdout, quoting=csv.QUOTE_MINIMAL)
for row in r:
    w.writerow(row)
" \
  | psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.recap_fjcintegrateddatabase (
  id, date_created, date_modified, dataset_source, office, docket_number,
  origin, date_filed, jurisdiction, nature_of_suit, title, section, subsection,
  diversity_of_residence, class_action, monetary_demand, county_of_residence,
  arbitration_at_filing, arbitration_at_termination,
  multidistrict_litigation_docket_number, plaintiff, defendant, date_transfer,
  transfer_office, transfer_docket_number, transfer_origin, date_terminated,
  termination_class_action_status, procedural_progress, disposition,
  nature_of_judgement, amount_received, judgment, pro_se, year_of_tape,
  nature_of_offense, version, circuit_id, district_id
) FROM STDIN WITH (FORMAT csv, HEADER)"

echo "Loading search_docket..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.search_docket (
  id, date_created, date_modified, source, appeal_from_str,
  assigned_to_str, referred_to_str, panel_str, date_last_index, date_cert_granted,
  date_cert_denied, date_argued, date_reargued, date_reargument_denied,
  date_filed, date_terminated, date_last_filing, case_name_short, case_name,
  case_name_full, slug, docket_number, docket_number_core, pacer_case_id, cause,
  nature_of_suit, jury_demand, jurisdiction_type, appellate_fee_status,
  appellate_case_type_information, mdl_status, filepath_local, filepath_ia,
  filepath_ia_json, ia_upload_failure_count, ia_needs_upload, ia_date_first_change,
  view_count, date_blocked, blocked, appeal_from_id, assigned_to_id, court_id,
  idb_data_id, originating_court_information_id, referred_to_id, federal_dn_case_type,
  federal_dn_office_code, federal_dn_judge_initials_assigned,
  federal_dn_judge_initials_referred, federal_defendant_number, parent_docket_id,
  docket_number_raw, docket_number_source
) FROM '$BASE/dockets-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading search_opinioncluster..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.search_opinioncluster (
  id, date_created, date_modified, judges, date_filed,
  date_filed_is_approximate, slug, case_name_short, case_name,
  case_name_full, scdb_id, scdb_decision_direction, scdb_votes_majority,
  scdb_votes_minority, source, procedural_history, attorneys,
  nature_of_suit, posture, syllabus, headnotes, summary, disposition,
  history, other_dates, cross_reference, correction, citation_count,
  precedential_status, date_blocked, blocked, filepath_json_harvard,
  filepath_pdf_harvard, docket_id, arguments, headmatter
) FROM '$BASE/opinion-clusters-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading search_opinion..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.search_opinion (
  id, date_created, date_modified, author_str, per_curiam, joined_by_str,
  type, sha1, page_count, download_url, local_path, plain_text, html,
  html_lawbox, html_columbia, html_anon_2020, xml_harvard, xml_scan,
  html_with_citations, extracted_by_ocr, author_id, cluster_id
) FROM '$BASE/opinions-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading search_opinioncluster_panel..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.search_opinioncluster_panel (
  id, opinioncluster_id, person_id
) FROM '$BASE/search_opinioncluster_panel-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading search_opinion_joined_by..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.search_opinion_joined_by (
  id, opinion_id, person_id
) FROM '$BASE/search_opinion_joined_by-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading search_opinioncluster_non_participating_judges..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.search_opinioncluster_non_participating_judges (
  id, opinioncluster_id, person_id
) FROM '$BASE/search_opinioncluster_non_participating_judges-2026-03-31.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

if [[ ! -f "$BASE/citation-map-2026-03-31_valid_only.csv" || \
      ! -f "$BASE/citations-2026-03-31_valid_only.csv" ]]; then
    echo "Preparing referentially valid citation files..."
    BULK_DB_NAME="$DB_NAME" BULK_DIR="$BASE" \
      python3 "$SCRIPT_DIR/prepare_citation_files.py"
fi

echo "Loading search_opinionscited..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.search_opinionscited (
  id, depth, cited_opinion_id, citing_opinion_id
) FROM '$BASE/citation-map-2026-03-31_valid_only.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Loading search_citation..."
psql $PSQL_OPTS -d "$DB_NAME" --command "\COPY public.search_citation (
  id, volume, reporter, page, type, cluster_id, date_created, date_modified
) FROM '$BASE/citations-2026-03-31_valid_only.csv' WITH (FORMAT csv, ENCODING utf8, ESCAPE E'\\\\', HEADER)"

echo "Done."
