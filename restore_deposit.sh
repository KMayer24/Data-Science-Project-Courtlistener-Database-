#!/usr/bin/env bash
# Restore a CourtListener Research Database Zenodo package into an empty
# PostgreSQL database and verify every file's checksum and row count.
set -euo pipefail

PACKAGE_DIR="${PACKAGE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)}"
RESTORE_DB="${RESTORE_DB:-courtlistener_release_restore}"
RESTORE_HOST="${RESTORE_HOST:-}"
RESTORE_PORT="${RESTORE_PORT:-5432}"

PSQL=(psql -X -q -v ON_ERROR_STOP=1 -p "$RESTORE_PORT" -d "$RESTORE_DB")
if [[ -n "$RESTORE_HOST" ]]; then PSQL+=( -h "$RESTORE_HOST" ); fi

for required in SHA256SUMS manifest.tsv release_schema.sql release_indexes.sql \
                12_validate_restored_release.sql; do
    [[ -f "$PACKAGE_DIR/$required" ]] || {
        echo "Missing package file: $required" >&2
        exit 1
    }
done

# Hosting repositories limit the size of a single file, so the largest archive
# is distributed as numbered parts.  Concatenating the parts in name order
# reproduces the original archive byte for byte, which is why the SHA-256
# digest recorded in manifest.tsv still describes the reassembled stream.
# parts.tsv lists which archives are split and the size and digest of each
# part.  Nothing else in this script needs to know the difference.
stream_archive() {
    local file="$1"
    if [[ -f "$PACKAGE_DIR/$file" ]]; then
        cat -- "$PACKAGE_DIR/$file"
        return
    fi
    local parts=( "$PACKAGE_DIR/$file".part* )
    if [[ ! -f "${parts[0]}" ]]; then
        echo "Missing $file: neither the archive nor its .part files are here" >&2
        return 1
    fi
    cat -- "${parts[@]}"
}

have_archive() {
    [[ -f "$PACKAGE_DIR/$1" ]] || compgen -G "$PACKAGE_DIR/$1.part*" >/dev/null
}

echo "Verifying SHA-256 checksums ..."
(cd "$PACKAGE_DIR" && sha256sum -c SHA256SUMS)

# SHA256SUMS covers the parts as they are shipped.  This second pass checks
# that they reassemble into the archive the manifest describes, reading the
# stream rather than writing a full copy to disk first.
if [[ -f "$PACKAGE_DIR/parts.tsv" ]]; then
    echo "Verifying reassembled archives ..."
    while IFS= read -r split_file; do
        expected="$(awk -F'\t' -v f="$split_file" '$1==f {print $6}' \
                        "$PACKAGE_DIR/manifest.tsv")"
        if [[ -z "$expected" ]]; then
            echo "No manifest entry for split archive $split_file" >&2
            exit 1
        fi
        actual="$(stream_archive "$split_file" | sha256sum | cut -d' ' -f1)"
        if [[ "$actual" != "$expected" ]]; then
            echo "Reassembled $split_file does not match its manifest digest." >&2
            echo "  expected $expected" >&2
            echo "  got      $actual" >&2
            exit 1
        fi
        echo "$split_file: OK (reassembled from parts)"
    done < <(tail -n +2 "$PACKAGE_DIR/parts.tsv" | cut -f1 | sort -u)
fi

"${PSQL[@]}" -Atc 'SELECT 1' >/dev/null || {
    echo "Create the empty target database first: createdb $RESTORE_DB" >&2
    exit 1
}

existing="$("${PSQL[@]}" -Atc "
  SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE c.relkind IN ('r','p') AND n.nspname IN ('public','deposit');")"
if [[ "$existing" != 0 ]]; then
    echo "Target database is not empty ($existing public/deposit tables)." >&2
    exit 2
fi

echo "Creating release tables ..."
"${PSQL[@]}" -f "$PACKAGE_DIR/release_schema.sql"

# Do not feed CSV data through psql's standard input.  Court opinions can
# legitimately contain a line consisting only of "\\." inside a quoted,
# multiline field.  psql treats that sequence as the end marker for COPY FROM
# STDIN before PostgreSQL's CSV parser sees it.  Reading from a named pipe as a
# file preserves the real end-of-file boundary and imports such text correctly.
fifo_dir="$(mktemp -d "${TMPDIR:-/tmp}/courtlistener-restore.XXXXXX")"
fifo="$fifo_dir/input.csv"
cleanup_fifo() {
    [[ ! -e "$fifo" && ! -p "$fifo" ]] || rm -f -- "$fifo"
    rmdir "$fifo_dir" 2>/dev/null || true
}
trap cleanup_fifo EXIT HUP INT TERM

tail -n +2 "$PACKAGE_DIR/manifest.tsv" \
  | while IFS=$'\t' read -r file schema relation expected_rows compressed_bytes digest; do
        have_archive "$file" || { echo "Missing $file" >&2; exit 1; }
        echo "Restoring $schema.$relation ($expected_rows rows) ..."
        rm -f -- "$fifo"
        mkfifo "$fifo"
        ( stream_archive "$file" | bunzip2 -c ) > "$fifo" &
        bunzip_pid=$!
        if ! "${PSQL[@]}" -c "\copy $schema.$relation FROM '$fifo' WITH (FORMAT csv, HEADER true)"; then
            kill "$bunzip_pid" 2>/dev/null || true
            wait "$bunzip_pid" 2>/dev/null || true
            exit 1
        fi
        if ! wait "$bunzip_pid"; then
            echo "Decompression failed for $file" >&2
            exit 1
        fi
        rm -f -- "$fifo"
        actual_rows="$("${PSQL[@]}" -Atc "SELECT count(*) FROM $schema.$relation;")"
        if [[ "$actual_rows" != "$expected_rows" ]]; then
            echo "Row-count mismatch for $schema.$relation: expected $expected_rows, got $actual_rows" >&2
            exit 1
        fi
    done

echo "Creating primary and foreign keys ..."
"${PSQL[@]}" -f "$PACKAGE_DIR/release_indexes.sql"
"${PSQL[@]}" -c 'ANALYZE;'

echo "Running release validation ..."
"${PSQL[@]}" -f "$PACKAGE_DIR/12_validate_restored_release.sql"
echo "Restore and validation complete in $RESTORE_DB."
