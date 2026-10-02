#!/usr/bin/env bash
# =====================================================================
# Upload the release package to a Zenodo draft record.
#
# The package lives on this server, so it is uploaded straight from here
# through the Zenodo files API rather than through the browser, which
# would mean downloading 58 GB to a laptop and sending it back up.
#
# Usage:
#   export ZENODO_TOKEN=...            # never pass the token on the command line
#   ./upload_zenodo.sh 23063945                 # every file in the package
#   ./upload_zenodo.sh 23063945 public_search_opinion.csv.bz2.part00  # one file
#
# The script is safe to re-run.  Before each file it asks Zenodo what is
# already in the record and skips anything whose MD5 already matches, so
# an interrupted run continues where it stopped.  After each upload it
# compares the MD5 Zenodo reports against the local one, which is what
# actually proves the transfer was clean.
#
# Run it under tmux.  58 GB over a university line takes hours:
#   tmux new -d -s zenodo_upload './upload_zenodo.sh 23063945 2>&1 | tee upload_zenodo.log'
# =====================================================================
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="${PACKAGE_DIR:-$SCRIPT_DIR/export/zenodo_v1}"
API="${ZENODO_API:-https://zenodo.org/api}"

DEPOSITION_ID="${1:-}"
ONLY_FILE="${2:-}"

if [[ -z "$DEPOSITION_ID" ]]; then
    sed -n '2,20p' "$0" >&2
    exit 2
fi
if [[ -z "${ZENODO_TOKEN:-}" ]]; then
    echo "ZENODO_TOKEN is not set.  export it first; do not pass it as an argument." >&2
    exit 2
fi
if [[ ! -d "$PACKAGE_DIR" ]]; then
    echo "Package directory not found: $PACKAGE_DIR" >&2
    exit 2
fi

auth=(-H "Authorization: Bearer $ZENODO_TOKEN")

# ---------------------------------------------------------------------
# The bucket is the record's file store.  Its URL is the only thing the
# upload needs, and it is only readable through the deposition endpoint.
# ---------------------------------------------------------------------
deposition="$(curl -sS "${auth[@]}" "$API/deposit/depositions/$DEPOSITION_ID")"
bucket="$(printf '%s' "$deposition" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("links",{}).get("bucket",""))')"

if [[ -z "$bucket" ]]; then
    echo "Could not read the bucket URL for deposition $DEPOSITION_ID." >&2
    echo "Check the id, the token, and that the record is still a draft." >&2
    printf '%s\n' "$deposition" | head -c 400 >&2
    exit 1
fi
echo "Bucket: $bucket"

# ---------------------------------------------------------------------
# What is already up there?  Zenodo reports an MD5 per file, so a file
# counts as done only if name and checksum both match.
# ---------------------------------------------------------------------
declare -A remote_md5=()
while IFS=$'\t' read -r name sum; do
    [[ -n "$name" ]] && remote_md5["$name"]="$sum"
done < <(curl -sS "${auth[@]}" "$API/deposit/depositions/$DEPOSITION_ID/files" |
         python3 -c '
import json, sys
try:
    for f in json.load(sys.stdin):
        print(f.get("filename", ""), f.get("checksum", "").replace("md5:", ""), sep="\t")
except Exception:
    pass')

if [[ -n "$ONLY_FILE" ]]; then
    files=("$ONLY_FILE")
else
    mapfile -t files < <(cd "$PACKAGE_DIR" && ls -1S)   # largest first
fi

total=${#files[@]}
i=0
failed=0

for f in "${files[@]}"; do
    i=$((i + 1))
    path="$PACKAGE_DIR/$f"
    if [[ ! -f "$path" ]]; then
        echo "[$i/$total] $f -- not found in the package, skipped" >&2
        failed=1
        continue
    fi

    size=$(stat -c%s "$path")
    printf '[%d/%d] %s (%.2f GB)\n' "$i" "$total" "$f" "$(echo "$size/1000000000" | bc -l)"

    local_md5=$(md5sum "$path" | cut -d' ' -f1)

    if [[ "${remote_md5[$f]:-}" == "$local_md5" ]]; then
        echo "        already uploaded, checksum matches, skipped"
        continue
    fi

    started=$(date +%s)
    response=$(curl -sS --fail-with-body --retry 3 --retry-delay 30 \
                    --upload-file "$path" "${auth[@]}" "$bucket/$f") || {
        echo "        UPLOAD FAILED" >&2
        printf '%s\n' "$response" | head -c 400 >&2
        failed=1
        continue
    }

    returned=$(printf '%s' "$response" |
               python3 -c 'import json,sys; print(json.load(sys.stdin).get("checksum","").replace("md5:",""))' 2>/dev/null)
    elapsed=$(( $(date +%s) - started ))

    if [[ "$returned" == "$local_md5" ]]; then
        printf '        ok, checksum verified, %d min\n' "$((elapsed / 60))"
    elif [[ -z "$returned" ]]; then
        # Zenodo answered with something other than the usual JSON, typically
        # an error page from its gateway.  The file may or may not have
        # landed; re-running settles it, because the record is asked first.
        echo "        NOT CONFIRMED: Zenodo returned no checksum" >&2
        failed=1
    else
        echo "        CHECKSUM MISMATCH: local $local_md5, Zenodo $returned" >&2
        failed=1
    fi
done

echo
if [[ $failed -eq 0 ]]; then
    echo "All files uploaded and verified.  The record is still a draft; nothing is public yet."
else
    echo "Finished with errors.  Re-run the script; completed files are skipped." >&2
fi
exit $failed
