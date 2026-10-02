#!/usr/bin/env bash
# Rebuild stages 01--04 into an isolated schema and verify the publication
# release against its expected counts and row-level regression checks.
#
# The source schema supplies the four preserved FJC input tables. Everything
# else is recomputed from public and the SQL under deposit_pipeline/.
set -euo pipefail

DB_NAME="${DB_NAME:-courtcase_db}"
DB_PORT="${DB_PORT:-5432}"
SOURCE_SCHEMA="${SOURCE_SCHEMA:-ext_release}"
TARGET_SCHEMA="${TARGET_SCHEMA:-ext_rebuild}"
REPLACE=false
GENDER_ONLY=false

usage() {
    sed -n '2,5p' "$0"
    echo "Usage: $0 [--target SCHEMA] [--source SCHEMA] [--gender-only] [--replace]"
}

while (($#)); do
    case "$1" in
        --target) TARGET_SCHEMA="$2"; shift 2 ;;
        --source) SOURCE_SCHEMA="$2"; shift 2 ;;
        --gender-only) GENDER_ONLY=true; shift ;;
        --replace) REPLACE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

for schema_name in "$SOURCE_SCHEMA" "$TARGET_SCHEMA"; do
    if [[ ! "$schema_name" =~ ^[a-z_][a-z0-9_]*$ ]]; then
        echo "Unsafe schema name: $schema_name" >&2
        exit 2
    fi
done

if [[ "$TARGET_SCHEMA" == public || "$TARGET_SCHEMA" == "$SOURCE_SCHEMA" ]]; then
    echo "Target must be an isolated schema, not '$TARGET_SCHEMA'." >&2
    exit 2
fi

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -r -- "$WORK_DIR"' EXIT
PSQL=(psql -X -v ON_ERROR_STOP=1 -p "$DB_PORT" -d "$DB_NAME")

schema_exists="$("${PSQL[@]}" -Atc "SELECT 1 FROM pg_namespace WHERE nspname = '$TARGET_SCHEMA'")"
if [[ "$schema_exists" == 1 && "$REPLACE" != true ]]; then
    echo "Schema $TARGET_SCHEMA already exists; pass --replace to rebuild it." >&2
    exit 2
fi

if [[ "$schema_exists" == 1 ]]; then
    "${PSQL[@]}" -c "DROP SCHEMA $TARGET_SCHEMA CASCADE;"
fi
"${PSQL[@]}" -c "CREATE SCHEMA $TARGET_SCHEMA;"

transform_and_run() {
    local relative_path="$1"
    local source_file="$ROOT_DIR/deposit_pipeline/$relative_path"
    local target_dir="$WORK_DIR/$(dirname -- "$relative_path")"
    local target_file="$target_dir/$(basename -- "$relative_path")"
    mkdir -p "$target_dir"
    sed "s/ext\./${TARGET_SCHEMA}./g" "$source_file" > "$target_file"

    echo "==> $relative_path"
    "${PSQL[@]}" -f "$target_file"
}

copy_input_table() {
    local table_name="$1"
    echo "==> input $SOURCE_SCHEMA.$table_name"
    "${PSQL[@]}" -c \
        "CREATE TABLE $TARGET_SCHEMA.$table_name AS TABLE $SOURCE_SCHEMA.$table_name;"
}

if [[ "$GENDER_ONLY" == true ]]; then
    # Fast repeat of the disputed stage: preserve its already-verified inputs.
    copy_input_table federal_appeal_courts
    copy_input_table excluded_appeals_named_courts
    copy_input_table federal_appeal_opinions
    copy_input_table federal_appeal_opinion_meta
    copy_input_table fjc_judge_bio
    copy_input_table fjc_judge_court
    copy_input_table fjc_court_name_map
    copy_input_table supplemental_judges
else
    # Corpus selection.
    transform_and_run 01_corpus_selection/01_select_federal_appeals_corpus.sql
    transform_and_run 01_corpus_selection/02_create_federal_appeals_opinions.sql

    # Preserved FJC judge inputs, followed by their reproducible crosswalk and
    # manual supplemental table.
    copy_input_table fjc_judge_bio
    copy_input_table fjc_judge_court
    transform_and_run 02_judge_reference/03_create_fjc_court_name_map.sql
    transform_and_run 02_judge_reference/04_create_supplemental_judges.sql
fi

# Four-stage gender assignment.
transform_and_run 03_gender_assignment/01_create_step1_author_id.sql
transform_and_run 03_gender_assignment/03_create_step2_author_str.sql
transform_and_run 03_gender_assignment/06_create_steps1_2_combined.sql
transform_and_run 03_gender_assignment/08_create_steps3_4_text_extraction.sql
transform_and_run 03_gender_assignment/09_create_final_gender_table.sql

if [[ "$GENDER_ONLY" != true ]]; then
    # Preserved FJC appellate inputs and reproducible case linkage.
    copy_input_table fjc_appellate_raw_1971to2007
    copy_input_table fjc_appellate_raw_2008plus
    transform_and_run 04_case_metadata/11_create_fjc_appellate_normalized.sql
    transform_and_run 04_case_metadata/19_build_fjc_opinion_matches.sql
    transform_and_run 04_case_metadata/20_fjc_code_crosswalks.sql
    transform_and_run 04_case_metadata/21_materialize_opinion_covariates.sql
fi

echo "==> publication-release regression"
"${PSQL[@]}" <<SQL
DO \$\$
DECLARE
    observed bigint[];
    observed_channels bigint[];
    required_release_row_ok boolean;
BEGIN
    SELECT ARRAY[
        COUNT(*),
        COUNT(*) FILTER (WHERE gender_resolved),
        COUNT(*) FILTER (WHERE gender = 'f'),
        COUNT(*) FILTER (WHERE gender = 'm')
    ] INTO observed
    FROM $TARGET_SCHEMA.author_gender_final_with_html;

    IF observed IS DISTINCT FROM ARRAY[1472533, 555297, 69936, 485361]::bigint[] THEN
        RAISE EXCEPTION
            'Release regression failed: observed %, expected {1472533,555297,69936,485361}',
            observed;
    END IF;

    EXECUTE format(
        'SELECT ARRAY['
        '  COUNT(*) FILTER (WHERE gender_resolved AND final_gender_assignment_channel = ''previous_final''), '
        '  COUNT(*) FILTER (WHERE gender_resolved AND final_gender_assignment_channel = ''xml_author_tag''), '
        '  COUNT(*) FILTER (WHERE gender_resolved AND final_gender_assignment_channel = ''html_extraction'')'
        '] FROM %I.author_gender_final_with_html',
        '$TARGET_SCHEMA'
    ) INTO observed_channels;

    IF observed_channels IS DISTINCT FROM ARRAY[418479, 11514, 125304]::bigint[] THEN
        RAISE EXCEPTION
            'Gender-channel regression failed: observed %, expected {418479,11514,125304}',
            observed_channels;
    END IF;

    EXECUTE format(
        'SELECT EXISTS ('
        '  SELECT 1 FROM %I.author_gender_final_with_html '
        '  WHERE opinion_id = 2966699 '
        '    AND gender = ''m'' '
        '    AND gender_resolved '
        '    AND final_gender_assignment_channel = ''html_extraction'' '
        '    AND html_extraction_pattern = ''A3_circuit_judge_line_pre_inline'' '
        '    AND html_extracted_author_name = ''LUTTIG'''
        ')',
        '$TARGET_SCHEMA'
    ) INTO required_release_row_ok;

    IF NOT required_release_row_ok THEN
        RAISE EXCEPTION
            'Required release attribution for opinion 2966699 is missing in %',
            '$TARGET_SCHEMA';
    END IF;
END
\$\$;

SELECT '$TARGET_SCHEMA' AS schema,
       COUNT(*) AS opinions,
       COUNT(*) FILTER (WHERE gender_resolved) AS gender_resolved,
       COUNT(*) FILTER (WHERE gender = 'f') AS female,
       COUNT(*) FILTER (WHERE gender = 'm') AS male
FROM $TARGET_SCHEMA.author_gender_final_with_html;
SQL

if [[ "$GENDER_ONLY" != true ]]; then
    echo "==> deterministic FJC-key regression"
    "${PSQL[@]}" <<SQL
DO \$\$
DECLARE
    expected_only bigint;
    actual_only bigint;
BEGIN
    WITH predicted AS MATERIALIZED (
        SELECT
            row_number() OVER (
                ORDER BY source_period, fjc_circuit_code, fjc_docket_raw,
                         docket_date_raw, judgment_date_raw,
                         reopen_code, appellant, appellee, appeal_type_code,
                         agency_code, jurisdiction_code, nature_of_suit_code,
                         offense_code, other_type_code, disposition_code,
                         outcome_code, opinion_code, tape_year_raw
            )::bigint AS fjc_appeal_id,
            source_period, court_id, fjc_circuit_code, fjc_docket_raw,
            reopen_code, docket_date_raw, judgment_date_raw, appellant,
            appellee, appeal_type_code, agency_code, jurisdiction_code,
            nature_of_suit_code, offense_code, other_type_code,
            disposition_code, outcome_code, opinion_code, tape_year_raw
        FROM $TARGET_SCHEMA.fjc_appellate_normalized
    )
    SELECT
        (SELECT count(*) FROM (
            SELECT * FROM predicted
            EXCEPT ALL
            SELECT * FROM $TARGET_SCHEMA.fjc_appellate_normalized
        ) x),
        (SELECT count(*) FROM (
            SELECT * FROM $TARGET_SCHEMA.fjc_appellate_normalized
            EXCEPT ALL
            SELECT * FROM predicted
        ) x)
    INTO expected_only, actual_only;

    IF expected_only <> 0 OR actual_only <> 0 THEN
        RAISE EXCEPTION
            'FJC key regression failed: expected_only=%, actual_only=%',
            expected_only, actual_only;
    END IF;
END
\$\$;
SQL
fi

echo "Rebuild complete in schema $TARGET_SCHEMA."
