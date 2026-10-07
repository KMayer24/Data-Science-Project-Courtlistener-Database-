#!/bin/bash
# =====================================================================
# build_deposit_db.sh -- build the submission database.
#
# Two databases, deliberately kept apart:
#
#   courtcase_db           the source research database, shared cluster,
#                          port 5432. READ-ONLY from this script.
#   courtlistener_deposit  the submission database. It lives in a
#                          SEPARATE PostgreSQL instance with its own data
#                          directory, its own port and its own server
#                          process, started under the user's own account
#                          because the shared cluster grants no CREATEDB.
#
# Example for a local submission instance (set DEPOSIT_DATA and DST_PORT
# for a different installation):
#   start  /usr/lib/postgresql/18/bin/pg_ctl -D /path/to/pg_deposit \
#            -l /path/to/pg_deposit/server.log \
#            -o "-p 5435 -k /path/to/pg_deposit" start
#   stop   /usr/lib/postgresql/18/bin/pg_ctl -D /path/to/pg_deposit stop
#   psql   psql -h /path/to/pg_deposit -p 5435 -d courtlistener_deposit
#   It does not survive a reboot; start it again when you need it.
#
# Schemas inside the submission database:
#   public   the CourtListener core tables
#   ext      validated publication-pipeline outputs copied as build inputs
#   deposit  the deposit-facing layer: neutral names, intermediates gone.
#
# Not copied, on purpose:
#   public.search_opinion                    160 GB. Deposited separately
#                                            as multipart source data. Use
#                                            --opinion-text to include it.
#   ext.federal_appeal_opinions              17 GB of text, duplicated
#                                            from public.search_opinion
#   ext.federal_appeals_opinion_header_text  materialised view, no script
#   ext.opinion_legal_domain                 no script, 42 % empty
#   ext.author_gender_author_id              superseded stage tables, not
#   ext.author_gender_author_str_fjc         needed to rebuild anything
#
# Usage:
#   ./build_deposit_db.sh --all            inputs + core + derived layer
#   ./build_deposit_db.sh --inputs         ext inputs only
#   ./build_deposit_db.sh --core           public core tables only
#   ./build_deposit_db.sh --derived        run the derived/deposit scripts
#   ./build_deposit_db.sh --opinion-text   add public.search_opinion (160 GB)
#   ./build_deposit_db.sh --keys           re-apply keys and indexes only
#   ./build_deposit_db.sh --report         what is in the database now
# =====================================================================
set -euo pipefail

SRC_DB="${SRC_DB:-courtcase_db}"
SRC_PORT="${SRC_PORT:-5432}"
SRC_EXT_SCHEMA="${SRC_EXT_SCHEMA:-ext_release}"
DST_DB="${DST_DB:-courtlistener_deposit}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPOSIT_DATA="${DEPOSIT_DATA:-$SCRIPT_DIR/.pg_deposit}"
DST_PORT="${DST_PORT:-5435}"
PIPELINE_DIR="$SCRIPT_DIR/deposit_pipeline/05_deposit"
MODE="${1:---all}"

if [[ ! "$SRC_EXT_SCHEMA" =~ ^[a-z_][a-z0-9_]*$ ]]; then
    echo "Unsafe source schema name: $SRC_EXT_SCHEMA" >&2
    exit 2
fi

DST=( -h "$DEPOSIT_DATA" -p "$DST_PORT" -d "$DST_DB" )

# Publication-pipeline outputs needed as build inputs or deposit tables.
EXT_INPUTS=(
  author_gender_final_with_html
  author_gender_final
  author_gender_from_text_extraction
  author_party_resolved
  federal_appeal_opinion_meta
  federal_appeal_courts
  excluded_appeals_named_courts
  fjc_judge_bio fjc_judge_court fjc_court_name_map supplemental_judges
  fjc_appellate_raw_1971to2007 fjc_appellate_raw_2008plus
  fjc_appellate_normalized fjc_opinion_match opinion_fjc_covariates
  fjc_domain_crosswalk fjc_outcome_crosswalk fjc_disposition_crosswalk
)

PUBLIC_CORE=(
  search_court search_docket search_opinioncluster search_citation
  search_opinionscited search_opinioncluster_panel search_opinion_joined_by
  search_opinioncluster_non_participating_judges
  people_db_person people_db_position people_db_education people_db_school
  people_db_politicalaffiliation people_db_person_race people_db_race
  recap_fjcintegrateddatabase
)

DERIVED_SCRIPTS=(
  01_unique_person_attribution.sql
  04_author_party_resolved.sql
  05_verify_author_party_resolved.sql
  08_author_party_timeaware.sql
  07_deposit_views.sql
)

require_instance () {
    if ! pg_isready -h "$DEPOSIT_DATA" -p "$DST_PORT" -q; then
        echo "The submission instance is not running. Start it with:"
        echo "  /usr/lib/postgresql/18/bin/pg_ctl -D $DEPOSIT_DATA \\"
        echo "    -l $DEPOSIT_DATA/server.log -o \"-p $DST_PORT -k $DEPOSIT_DATA\" start"
        exit 1
    fi
}

copy_tables () {   # copy_tables <source_schema> <destination_schema> <force> <table...>
    local source_schema="$1" destination_schema="$2" force="$3"; shift 3
    local t src_n dst_n
    for t in "$@"; do
        src_n=$(psql -p "$SRC_PORT" -d "$SRC_DB" -At \
                     -c "SELECT count(*) FROM ${source_schema}.${t};")

        # Existence and row count must be two statements: PostgreSQL parses
        # the whole query up front, so counting a missing relation is a parse
        # error even inside an untaken CASE branch.
        if psql "${DST[@]}" -At -c \
             "SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = '${destination_schema}' AND c.relname = '${t}';" | grep -q 1
        then
            dst_n=$(psql "${DST[@]}" -At -c "SELECT count(*) FROM ${destination_schema}.${t};")
        else
            dst_n=-1
        fi

        if [[ "$force" != true && "$dst_n" == "$src_n" ]]; then
            printf '    %-46s %12s rows (present)\n' "$destination_schema.$t" "$dst_n"
            continue
        fi

        # Anything short of an exact match is rebuilt: a partial copy from an
        # interrupted run is worse than no copy.
        #
        # Structure and data only. Constraints and indexes are deliberately
        # left for the post-data pass, because pg_dump emits each table's
        # foreign keys with the table, and three of them point at
        # public.search_opinion, which this database does not carry. Restoring
        # them inline aborts the whole copy.
        printf '    %-46s %12s rows ' "$destination_schema.$t" "$src_n"
        psql "${DST[@]}" -q -c "DROP TABLE IF EXISTS ${destination_schema}.${t} CASCADE;" 2>/dev/null
        pg_dump -p "$SRC_PORT" -d "$SRC_DB" --no-owner --no-privileges \
                --section=pre-data --section=data -t "${source_schema}.${t}" \
            | sed "s/${source_schema}\./${destination_schema}./g" \
            | psql "${DST[@]}" -q -v ON_ERROR_STOP=1 >/dev/null

        dst_n=$(psql "${DST[@]}" -At -c "SELECT count(*) FROM ${destination_schema}.${t};")
        if [[ "$dst_n" != "$src_n" ]]; then
            printf 'MISMATCH (copied %s)\n' "$dst_n"
            echo "ABORT: $destination_schema.$t did not copy completely." >&2
            exit 1
        fi
        printf 'copied\n'
    done
}

apply_post_data () {   # apply_post_data <source_schema> <destination_schema> <table...>
    # Primary keys, indexes and foreign keys, once every table exists.
    #
    # Two passes, deliberately. pg_dump emits a table's foreign keys together
    # with its own indexes, so a key pointing at a table whose primary key has
    # not been created yet fails. Processing order cannot fix that in general
    # (cycles are legal), so the first pass creates the keys and indexes and
    # the second picks up the foreign keys that now have something to point
    # at. Re-running is harmless: existing objects simply report "already
    # exists".
    local source_schema="$1" destination_schema="$2"; shift 2
    local pass t log
    log="$(mktemp)"
    echo "Applying keys and indexes ..."
    for pass in 1 2; do
        : > "$log"
        for t in "$@"; do
            pg_dump -p "$SRC_PORT" -d "$SRC_DB" --no-owner --no-privileges \
                    --section=post-data -t "${source_schema}.${t}" \
                | sed "s/${source_schema}\./${destination_schema}./g" \
                | psql "${DST[@]}" -q >>"$log" 2>&1 || true
        done
    done

    # Only the second pass matters, and only failures that are not "this is
    # already there". What survives that filter is a real gap.
    local real
    real=$(grep 'ERROR' "$log" \
           | grep -vE 'already exists|multiple primary keys' | sort -u || true)
    if [[ -n "$real" ]]; then
        echo "  could not be applied:"
        sed 's/^/    /' <<<"$real"
        echo "  Foreign keys into public.search_opinion are expected to fail:"
        echo "  this database does not carry that table. Run --opinion-text"
        echo "  to add it, then --keys to complete them."
    else
        echo "  all applied"
    fi
    rm -f "$log"
}

release_assert_sql () {   # release_assert_sql <schema>
    local schema="$1"
    cat <<SQL
DO \$\$
DECLARE
    gender_counts bigint[];
    gender_channels bigint[];
    fjc_counts bigint[];
    required_release_row_ok boolean;
BEGIN
    SELECT ARRAY[
        count(*),
        count(*) FILTER (WHERE gender_resolved),
        count(*) FILTER (WHERE gender = 'f'),
        count(*) FILTER (WHERE gender = 'm')
    ]
    INTO gender_counts
    FROM ${schema}.author_gender_final_with_html;

    IF gender_counts IS DISTINCT FROM
       ARRAY[1472533, 555297, 69936, 485361]::bigint[] THEN
        RAISE EXCEPTION
            'Publication gender counts failed in ${schema}: observed %, expected {1472533,555297,69936,485361}',
            gender_counts;
    END IF;

    SELECT ARRAY[
        count(*) FILTER (
            WHERE gender_resolved
              AND final_gender_assignment_channel = 'previous_final'
        ),
        count(*) FILTER (
            WHERE gender_resolved
              AND final_gender_assignment_channel = 'xml_author_tag'
        ),
        count(*) FILTER (
            WHERE gender_resolved
              AND final_gender_assignment_channel = 'html_extraction'
        )
    ]
    INTO gender_channels
    FROM ${schema}.author_gender_final_with_html;

    IF gender_channels IS DISTINCT FROM
       ARRAY[418479, 11514, 125304]::bigint[] THEN
        RAISE EXCEPTION
            'Publication gender channels failed in ${schema}: observed %, expected {418479,11514,125304}',
            gender_channels;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM ${schema}.author_gender_final_with_html
        WHERE opinion_id = 2966699
          AND gender = 'm'
          AND gender_resolved
          AND final_gender_assignment_channel = 'html_extraction'
          AND html_extraction_pattern = 'A3_circuit_judge_line_pre_inline'
          AND html_extracted_author_name = 'LUTTIG'
    )
    INTO required_release_row_ok;

    IF NOT required_release_row_ok THEN
        RAISE EXCEPTION
            'Required publication attribution for opinion 2966699 is missing in ${schema}';
    END IF;

    SELECT ARRAY[
        (SELECT count(*) FROM ${schema}.fjc_appellate_normalized),
        (SELECT count(*) FROM ${schema}.fjc_opinion_match),
        (SELECT count(*) FROM ${schema}.opinion_fjc_covariates),
        (SELECT count(*)
         FROM ${schema}.opinion_fjc_covariates
         WHERE analysis_eligible)
    ]
    INTO fjc_counts;

    IF fjc_counts IS DISTINCT FROM
       ARRAY[2403096, 1414601, 1164762, 1069145]::bigint[] THEN
        RAISE EXCEPTION
            'Publication FJC counts failed in ${schema}: observed %, expected {2403096,1414601,1164762,1069145}',
            fjc_counts;
    END IF;
END
\$\$;
SQL
}

validate_source_release () {
    echo "Validating source release $SRC_EXT_SCHEMA ..."
    release_assert_sql "$SRC_EXT_SCHEMA" \
        | psql -X -p "$SRC_PORT" -d "$SRC_DB" -q -v ON_ERROR_STOP=1
}

validate_destination_release () {
    echo "Validating copied release schema ext ..."
    release_assert_sql ext \
        | psql -X "${DST[@]}" -q -v ON_ERROR_STOP=1
}

do_inputs () {
    validate_source_release
    echo "Copying publication outputs from $SRC_EXT_SCHEMA into schema ext ..."
    psql "${DST[@]}" -q -v ON_ERROR_STOP=1 -c "CREATE SCHEMA IF NOT EXISTS ext;"
    copy_tables "$SRC_EXT_SCHEMA" ext true "${EXT_INPUTS[@]}"
    apply_post_data "$SRC_EXT_SCHEMA" ext "${EXT_INPUTS[@]}"
    validate_destination_release
}

do_core () {
    echo "Copying CourtListener core tables into schema public ..."
    copy_tables public public false "${PUBLIC_CORE[@]}"
    apply_post_data public public "${PUBLIC_CORE[@]}"
}

do_derived () {
    validate_destination_release
    echo "Building the derived and deposit layers ..."
    local f
    # Views in the generated presentation layer depend on ext tables that are
    # rebuilt below. Remove the view layer first; 07 recreates it last.
    psql "${DST[@]}" -q -v ON_ERROR_STOP=1 \
        -c "DROP SCHEMA IF EXISTS deposit CASCADE;"
    for f in "${DERIVED_SCRIPTS[@]}"; do
        echo "    $f"
        psql "${DST[@]}" -q -v ON_ERROR_STOP=1 -f "$PIPELINE_DIR/$f"
    done
    psql "${DST[@]}" -q -c "ANALYZE;"
}

do_report () {
    psql "${DST[@]}" -c "
    SELECT n.nspname AS schema, count(*) AS relations,
           pg_size_pretty(sum(pg_total_relation_size(c.oid))) AS size
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r','m','v') AND n.nspname IN ('public','ext','deposit')
    GROUP BY 1 ORDER BY 1;"
}

case "$MODE" in
  --all)          require_instance; do_inputs; do_core; do_derived; do_report ;;
  --inputs)       require_instance; do_inputs; do_report ;;
  --core)         require_instance; do_core; do_report ;;
  --derived)      require_instance; do_derived; do_report ;;
  --opinion-text) require_instance
                  echo "Copying public.search_opinion (160 GB, hours) ..."
                  copy_tables public public false search_opinion; do_report ;;
  --keys)         require_instance
                  apply_post_data "$SRC_EXT_SCHEMA" ext "${EXT_INPUTS[@]}"
                  apply_post_data public public "${PUBLIC_CORE[@]}" ;;
  --report)       require_instance; do_report ;;
  *) sed -n '38,45p' "$0"; exit 2 ;;
esac
