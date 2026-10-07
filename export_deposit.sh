#!/usr/bin/env bash
# Export the publication database as deterministic, table-wise CSV/BZip2.
#
# The derived/core relations live in the isolated submission database.  The
# 160-GB PostgreSQL opinion-text table deliberately stays in the read-only
# source database and is streamed from there.  A complete --all export is one
# Zenodo dataset record, not two independent records.
#
# Usage:
#   ./export_deposit.sh --dry-run
#   ./export_deposit.sh --derived
#   ./export_deposit.sh --record-a
#   ./export_deposit.sh --record-b
#   ./export_deposit.sh --all
#   ./export_deposit.sh --package-only /path/to/existing/export
#
# Defaults:
#   submission database: courtlistener_deposit, socket/port 5435
#   source database:     courtcase_db, port 5432
#   output:              export/zenodo_v1
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/export/zenodo_v1}"
JOBS="${JOBS:-4}"
MODE="${1:---dry-run}"
PACKAGE_ONLY_DIR="${2:-$OUT_DIR}"
MAX_ARCHIVE_BYTES=50000000000
PART_BYTES=9000000000

DEPOSIT_DB="${DEPOSIT_DB:-courtlistener_deposit}"
DEPOSIT_HOST="${DEPOSIT_HOST:-$ROOT_DIR/.pg_deposit}"
DEPOSIT_PORT="${DEPOSIT_PORT:-5435}"
SOURCE_DB="${SOURCE_DB:-courtcase_db}"
SOURCE_HOST="${SOURCE_HOST:-}"
SOURCE_PORT="${SOURCE_PORT:-5432}"

DEPOSIT_PSQL=(psql -X -q -v ON_ERROR_STOP=1 -h "$DEPOSIT_HOST" -p "$DEPOSIT_PORT" -d "$DEPOSIT_DB")
SOURCE_PSQL=(psql -X -q -v ON_ERROR_STOP=1 -p "$SOURCE_PORT" -d "$SOURCE_DB")
if [[ -n "$SOURCE_HOST" ]]; then
    SOURCE_PSQL+=( -h "$SOURCE_HOST" )
fi

CORE_TABLES=(
  search_court search_docket search_opinioncluster search_citation
  search_opinionscited search_opinioncluster_panel search_opinion_joined_by
  search_opinioncluster_non_participating_judges
  people_db_person people_db_position people_db_education people_db_school
  people_db_politicalaffiliation people_db_person_race people_db_race
  recap_fjcintegrateddatabase
)

DERIVED_VIEWS=(
  appellate_court appellate_court_excluded appellate_opinion
  judge_biography judge_service judge_court_name_map judge_supplemental
  opinion_author_attribution opinion_author_attribution_diagnostics
  opinion_author_party
  fjc_appellate_raw_1971to2007 fjc_appellate_raw_2008plus
  fjc_appellate_case opinion_fjc_match opinion_case_covariates
  crosswalk_case_domain crosswalk_outcome crosswalk_disposition
)

# Stable row order for every deposited relation.  The two raw FJC tables have
# no source identifier; all their columns are used below.  Rows tied on every
# column are identical, so swapping such rows cannot change the CSV bytes.
declare -A ORDER_BY=(
  [deposit.appellate_court]='court_id COLLATE "C"'
  [deposit.appellate_court_excluded]='court_id COLLATE "C"'
  [deposit.appellate_opinion]='opinion_id'
  [deposit.judge_biography]='judge_nid'
  [deposit.judge_service]='service_id'
  [deposit.judge_court_name_map]='court_id COLLATE "C"'
  [deposit.judge_supplemental]='supplemental_id'
  [deposit.opinion_author_attribution]='opinion_id'
  [deposit.opinion_author_attribution_diagnostics]='opinion_id'
  [deposit.opinion_author_party]='opinion_id'
  [deposit.fjc_appellate_case]='fjc_appeal_id'
  [deposit.opinion_fjc_match]='opinion_id'
  [deposit.opinion_case_covariates]='opinion_id'
  [deposit.crosswalk_case_domain]='code_kind COLLATE "C", code_value COLLATE "C"'
  [deposit.crosswalk_outcome]='outcome_code COLLATE "C"'
  [deposit.crosswalk_disposition]='disposition_code COLLATE "C"'
)

compressor() {
    if command -v pbzip2 >/dev/null 2>&1; then
        pbzip2 -c -9 -p"$JOBS"
    else
        bzip2 -c -9
    fi
}

require_databases() {
    pg_isready -h "$DEPOSIT_HOST" -p "$DEPOSIT_PORT" -d "$DEPOSIT_DB" -q || {
        echo "Submission database is not available at $DEPOSIT_HOST:$DEPOSIT_PORT/$DEPOSIT_DB" >&2
        exit 1
    }
    "${SOURCE_PSQL[@]}" -Atc 'SELECT 1' >/dev/null
}

all_column_order() { # all_column_order <schema> <relation>
    local schema="$1" relation="$2"
    "${DEPOSIT_PSQL[@]}" -Atc "
      SELECT string_agg(
          format('%I%s NULLS FIRST', a.attname,
                 CASE WHEN t.typcollation <> 0 THEN ' COLLATE \"C\"' ELSE '' END),
          ', ' ORDER BY a.attnum)
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_type t ON t.oid = a.atttypid
      WHERE n.nspname = '$schema' AND c.relname = '$relation'
        AND a.attnum > 0 AND NOT a.attisdropped;"
}

order_for() { # order_for <schema> <relation>
    local schema="$1" relation="$2" key="$1.$2"
    if [[ -n "${ORDER_BY[$key]:-}" ]]; then
        printf '%s' "${ORDER_BY[$key]}"
    elif [[ "$schema" == public ]]; then
        # Every deposited public table has a source primary key named id.
        printf '%s' 'id'
    else
        all_column_order "$schema" "$relation"
    fi
}

relation_exists() { # relation_exists <deposit|source> <schema> <relation>
    local which="$1" schema="$2" relation="$3"
    local -a conn
    if [[ "$which" == deposit ]]; then conn=("${DEPOSIT_PSQL[@]}"); else conn=("${SOURCE_PSQL[@]}"); fi
    [[ "$("${conn[@]}" -Atc "SELECT to_regclass('$schema.$relation') IS NOT NULL;")" == t ]]
}

row_count() { # row_count <deposit|source> <schema> <relation>
    local which="$1" schema="$2" relation="$3"
    if [[ "$which" == deposit ]]; then
        "${DEPOSIT_PSQL[@]}" -Atc "SELECT count(*) FROM $schema.$relation;"
    else
        "${SOURCE_PSQL[@]}" -Atc "SELECT count(*) FROM $schema.$relation;"
    fi
}

relation_size() { # relation_size <deposit|source> <schema> <relation>
    local which="$1" schema="$2" relation="$3"
    if [[ "$which" == deposit ]]; then
        "${DEPOSIT_PSQL[@]}" -Atc "SELECT pg_size_pretty(pg_total_relation_size('$schema.$relation'));"
    else
        "${SOURCE_PSQL[@]}" -Atc "SELECT pg_size_pretty(pg_total_relation_size('$schema.$relation'));"
    fi
}

validate_release() {
    echo "Validating publication release before export ..."
    "${DEPOSIT_PSQL[@]}" <<'SQL'
DO $$
DECLARE
    gender_counts bigint[];
    fjc_counts bigint[];
BEGIN
    SELECT ARRAY[
        count(*), count(*) FILTER (WHERE gender_resolved),
        count(*) FILTER (WHERE gender = 'f'),
        count(*) FILTER (WHERE gender = 'm')
    ] INTO gender_counts
    FROM deposit.opinion_author_attribution;

    IF gender_counts IS DISTINCT FROM ARRAY[1472533,555297,69936,485361]::bigint[] THEN
        RAISE EXCEPTION 'Gender release check failed: %', gender_counts;
    END IF;

    SELECT ARRAY[
        (SELECT count(*) FROM deposit.fjc_appellate_case),
        (SELECT count(*) FROM deposit.opinion_fjc_match),
        (SELECT count(*) FROM deposit.opinion_case_covariates),
        (SELECT count(*) FROM deposit.opinion_case_covariates WHERE analysis_eligible)
    ] INTO fjc_counts;

    IF fjc_counts IS DISTINCT FROM ARRAY[2403096,1414601,1164762,1069145]::bigint[] THEN
        RAISE EXCEPTION 'FJC release check failed: %', fjc_counts;
    END IF;
END $$;
SQL
}

append_table_schema() { # <deposit|source> <source_schema> <relation> <target_schema> <file>
    local which="$1" schema="$2" relation="$3" target_schema="$4" file="$5"
    local -a conn
    if [[ "$which" == deposit ]]; then conn=("${DEPOSIT_PSQL[@]}"); else conn=("${SOURCE_PSQL[@]}"); fi
    "${conn[@]}" -Atc "
      SELECT format('CREATE TABLE %I.%I (' || E'\\n' || '%s' || E'\\n' || ');',
                    '$target_schema', '$relation',
             string_agg(
                 format('    %I %s%s', a.attname,
                        pg_catalog.format_type(a.atttypid, a.atttypmod),
                        CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END),
                 E',\\n' ORDER BY a.attnum))
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = '$schema' AND c.relname = '$relation'
        AND a.attnum > 0 AND NOT a.attisdropped;" >> "$file"
    printf '\n' >> "$file"
}

append_dictionary() { # <deposit|source> <schema> <relation> <file>
    local which="$1" schema="$2" relation="$3" file="$4"
    local -a conn
    if [[ "$which" == deposit ]]; then conn=("${DEPOSIT_PSQL[@]}"); else conn=("${SOURCE_PSQL[@]}"); fi
    "${conn[@]}" -F $'\t' -Atc "
      SELECT '$schema', '$relation', a.attnum, a.attname,
             pg_catalog.format_type(a.atttypid, a.atttypmod),
             CASE WHEN a.attnotnull THEN 'no' ELSE 'yes' END
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = '$schema' AND c.relname = '$relation'
        AND a.attnum > 0 AND NOT a.attisdropped
      ORDER BY a.attnum;" >> "$file"
}

dump_one() { # <deposit|source> <schema> <relation> <staging_dir>
    local which="$1" schema="$2" relation="$3" staging="$4"
    local file="${schema}_${relation}.csv.bz2" out="$staging/${schema}_${relation}.csv.bz2"
    local ordering rows bytes digest
    local -a conn
    if [[ "$which" == deposit ]]; then conn=("${DEPOSIT_PSQL[@]}"); else conn=("${SOURCE_PSQL[@]}"); fi
    ordering="$(order_for "$schema" "$relation")"
    rows="$(row_count "$which" "$schema" "$relation")"
    printf '  %-58s %12s rows\n' "$schema.$relation" "$rows"
    "${conn[@]}" -c "\copy (SELECT * FROM $schema.$relation ORDER BY $ordering) TO STDOUT WITH (FORMAT csv, HEADER true)" \
        | compressor > "$out"
    bytes="$(stat -c%s "$out")"
    digest="$(sha256sum "$out" | cut -d' ' -f1)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$file" "$schema" "$relation" "$rows" "$bytes" "$digest" >> "$staging/manifest.tsv"
}

package_large_archives() { # <staging_dir>
    local staging="$1"
    local parts_tmp="$staging/.parts.tsv.$$"
    local have_parts=false
    local file schema relation rows compressed_bytes digest archive actual
    local part part_name part_bytes part_digest
    local -a parts=()

    [[ -f "$staging/manifest.tsv" ]] || {
        echo "Missing manifest: $staging/manifest.tsv" >&2
        return 1
    }

    printf 'archive\tpart\tbytes\tsha256\n' > "$parts_tmp"
    while IFS=$'\t' read -r file schema relation rows compressed_bytes digest; do
        [[ "$compressed_bytes" =~ ^[0-9]+$ ]] || {
            echo "Invalid compressed size for $file: $compressed_bytes" >&2
            rm -f -- "$parts_tmp"
            return 1
        }
        (( compressed_bytes > MAX_ARCHIVE_BYTES )) || continue
        have_parts=true
        archive="$staging/$file"

        # A fresh export has the whole archive.  A repeated packaging run has
        # only the numbered parts.  If a prior split was interrupted while the
        # whole archive still exists, replace only those incomplete part files.
        if [[ -f "$archive" ]]; then
            rm -f -- "$archive".part[0-9][0-9]
            split -b "$PART_BYTES" -d -a 2 -- "$archive" "$archive.part"
        fi

        mapfile -t parts < <(
            find "$staging" -maxdepth 1 -type f \
                -name "$file.part[0-9][0-9]" -printf '%p\n' | LC_ALL=C sort
        )
        if ((${#parts[@]} == 0)); then
            echo "Missing oversized archive and parts: $file" >&2
            rm -f -- "$parts_tmp"
            return 1
        fi

        actual="$(cat -- "${parts[@]}" | sha256sum | cut -d' ' -f1)"
        if [[ "$actual" != "$digest" ]]; then
            echo "Parts for $file do not reproduce its manifest digest." >&2
            echo "  expected $digest" >&2
            echo "  got      $actual" >&2
            rm -f -- "$parts_tmp"
            return 1
        fi

        for part in "${parts[@]}"; do
            part_name="${part##*/}"
            part_bytes="$(stat -c%s "$part")"
            if (( part_bytes > PART_BYTES )); then
                echo "Part exceeds $PART_BYTES bytes: $part_name" >&2
                rm -f -- "$parts_tmp"
                return 1
            fi
            part_digest="$(sha256sum "$part" | cut -d' ' -f1)"
            printf '%s\t%s\t%s\t%s\n' \
                "$file" "$part_name" "$part_bytes" "$part_digest" >> "$parts_tmp"
        done

        # The upload contains the parts, while manifest.tsv deliberately keeps
        # the size and digest of the byte-identical reassembled archive.
        rm -f -- "$archive"
    done < <(tail -n +2 "$staging/manifest.tsv")

    if [[ "$have_parts" == true ]]; then
        mv -- "$parts_tmp" "$staging/parts.tsv"
    else
        rm -f -- "$parts_tmp" "$staging/parts.tsv"
    fi
}

write_sha256s() { # <package_dir>
    local package_dir="$1"
    (
      cd "$package_dir"
      find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' \
          | LC_ALL=C sort | xargs sha256sum > SHA256SUMS
    )
}

prepare_metadata() { # <staging_dir> <include_core> <include_derived> <include_opinion>
    local staging="$1" include_core="$2" include_derived="$3" include_opinion="$4" t
    local schema_file="$staging/release_schema.sql"
    local index_file="$staging/release_indexes.sql"
    local dictionary="$staging/data_dictionary.tsv"

    printf '%s\n' '-- Generated schema for the CourtListener Research Database release.' \
        'CREATE SCHEMA IF NOT EXISTS public;' \
        'CREATE SCHEMA IF NOT EXISTS deposit;' '' > "$schema_file"
    printf 'schema\trelation\tordinal_position\tcolumn_name\tpostgres_type\tnullable\n' > "$dictionary"
    printf '%s\n' '-- Indexes applied after the CSV files have been restored.' > "$index_file"

    if [[ "$include_core" == true ]]; then
        for t in "${CORE_TABLES[@]}"; do
            append_table_schema deposit public "$t" public "$schema_file"
            append_dictionary deposit public "$t" "$dictionary"
            printf 'ALTER TABLE public.%s ADD PRIMARY KEY (id);\n' "$t" >> "$index_file"
        done
    fi
    if [[ "$include_opinion" == true ]]; then
        append_table_schema source public search_opinion public "$schema_file"
        append_dictionary source public search_opinion "$dictionary"
        printf 'ALTER TABLE public.search_opinion ADD PRIMARY KEY (id);\n' >> "$index_file"
    fi
    if [[ "$include_core" == true && "$include_opinion" == true ]]; then
        cat >> "$index_file" <<'SQL'
ALTER TABLE public.search_opinion_joined_by
    ADD CONSTRAINT fk_joinedby_opinion
    FOREIGN KEY (opinion_id) REFERENCES public.search_opinion(id)
    DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE public.search_opinionscited
    ADD CONSTRAINT fk_opinionscited_cited
    FOREIGN KEY (cited_opinion_id) REFERENCES public.search_opinion(id)
    DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE public.search_opinionscited
    ADD CONSTRAINT fk_opinionscited_citing
    FOREIGN KEY (citing_opinion_id) REFERENCES public.search_opinion(id)
    DEFERRABLE INITIALLY DEFERRED;
SQL
    fi
    if [[ "$include_derived" == true ]]; then
        for t in "${DERIVED_VIEWS[@]}"; do
            append_table_schema deposit deposit "$t" deposit "$schema_file"
            append_dictionary deposit deposit "$t" "$dictionary"
        done
        cat >> "$index_file" <<'SQL'
ALTER TABLE deposit.appellate_court ADD PRIMARY KEY (court_id);
ALTER TABLE deposit.appellate_court_excluded ADD PRIMARY KEY (court_id);
ALTER TABLE deposit.appellate_opinion ADD PRIMARY KEY (opinion_id);
ALTER TABLE deposit.judge_biography ADD PRIMARY KEY (judge_nid);
ALTER TABLE deposit.judge_service ADD PRIMARY KEY (service_id);
ALTER TABLE deposit.judge_court_name_map ADD PRIMARY KEY (court_id);
ALTER TABLE deposit.judge_supplemental ADD PRIMARY KEY (supplemental_id);
ALTER TABLE deposit.opinion_author_attribution ADD PRIMARY KEY (opinion_id);
ALTER TABLE deposit.opinion_author_attribution_diagnostics ADD PRIMARY KEY (opinion_id);
ALTER TABLE deposit.opinion_author_party ADD PRIMARY KEY (opinion_id);
ALTER TABLE deposit.fjc_appellate_case ADD PRIMARY KEY (fjc_appeal_id);
ALTER TABLE deposit.opinion_fjc_match ADD PRIMARY KEY (opinion_id);
ALTER TABLE deposit.opinion_case_covariates ADD PRIMARY KEY (opinion_id);
ALTER TABLE deposit.crosswalk_case_domain ADD PRIMARY KEY (code_kind, code_value);
ALTER TABLE deposit.crosswalk_outcome ADD PRIMARY KEY (outcome_code);
ALTER TABLE deposit.crosswalk_disposition ADD PRIMARY KEY (disposition_code);
SQL
    fi
}

finalize_package() { # <staging_dir>
    local staging="$1"
    cp "$ROOT_DIR/restore_deposit.sh" "$staging/"
    cp "$ROOT_DIR/DATA_LICENSES.md" "$staging/"
    cp "$ROOT_DIR/deposit_pipeline/DATA_DEPOSIT_README.md" "$staging/README_DATA.md"
    cp "$ROOT_DIR/deposit_pipeline/05_deposit/12_validate_restored_release.sql" "$staging/"
    chmod +x "$staging/restore_deposit.sh"
    write_sha256s "$staging"
}

package_only() { # <existing_export_dir>
    local package_dir="$1"
    [[ -d "$package_dir" ]] || {
        echo "Package directory not found: $package_dir" >&2
        exit 2
    }
    package_large_archives "$package_dir"
    write_sha256s "$package_dir"
    echo "Packaging complete without database export: $package_dir"
}

sizes_only() {
    require_databases
    validate_release
    echo "Relation                                                    Rows      PostgreSQL size"
    echo "--------------------------------------------------------------------------------"
    local t rows size
    for t in "${DERIVED_VIEWS[@]}"; do
        rows="$(row_count deposit deposit "$t")"
        printf 'deposit.%-46s %12s\n' "$t" "$rows"
    done
    for t in "${CORE_TABLES[@]}"; do
        size="$(relation_size deposit public "$t")"
        printf 'public.%-47s %12s\n' "$t" "$size"
    done
    size="$(relation_size source public search_opinion)"
    rows="$(row_count source public search_opinion)"
    printf 'public.%-47s %12s  (%s rows)\n' search_opinion "$size" "$rows"
    echo
    echo "These are database sizes, not compressed upload sizes."
}

run_export() { # <derived|record-a|record-b|all>
    local selection="$1" t staging
    local include_core=false include_derived=false include_opinion=false
    require_databases
    validate_release
    case "$selection" in
      derived)  include_derived=true ;;
      record-a) include_core=true; include_derived=true ;;
      record-b) include_opinion=true ;;
      all)      include_core=true; include_derived=true; include_opinion=true ;;
    esac

    if [[ -e "$OUT_DIR" ]]; then
        echo "Output path already exists: $OUT_DIR" >&2
        echo "Choose a new OUT_DIR; existing release files are never overwritten." >&2
        exit 2
    fi
    staging="${OUT_DIR}.partial.$$"
    mkdir -p "$staging"
    printf 'file\tschema\trelation\trows\tcompressed_bytes\tsha256\n' > "$staging/manifest.tsv"
    prepare_metadata "$staging" "$include_core" "$include_derived" "$include_opinion"

    if [[ "$include_derived" == true ]]; then
        echo "Exporting derived tables ..."
        for t in "${DERIVED_VIEWS[@]}"; do dump_one deposit deposit "$t" "$staging"; done
    fi
    if [[ "$include_core" == true ]]; then
        echo "Exporting core metadata tables ..."
        for t in "${CORE_TABLES[@]}"; do dump_one deposit public "$t" "$staging"; done
    fi
    if [[ "$include_opinion" == true ]]; then
        echo "Exporting opinion texts ..."
        dump_one source public search_opinion "$staging"
    fi

    package_large_archives "$staging"
    finalize_package "$staging"
    mv "$staging" "$OUT_DIR"
    echo "Release package complete: $OUT_DIR"
    du -sh "$OUT_DIR"
}

case "$MODE" in
  --dry-run)  sizes_only ;;
  --derived)  run_export derived ;;
  --record-a) run_export record-a ;;
  --record-b) run_export record-b ;;
  --all)      run_export all ;;
  --package-only) package_only "$PACKAGE_ONLY_DIR" ;;
  *) echo "Unknown mode: $MODE" >&2; exit 2 ;;
esac
