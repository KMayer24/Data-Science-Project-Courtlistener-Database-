#!/bin/bash
# =====================================================================
# run_validation.sh -- single entry point for validating the database.
#
# Reproduces every validation figure the data paper reports:
#   1. row counts for all core tables
#   2. foreign-key / referential-integrity checks
#   3. variable completeness (missingness) per table
#   4. coverage of the derived (ext) layer
#
# Usage:
#   ./run_validation.sh                  # run everything, write a report
#   ./run_validation.sh --core           # core (public) checks only
#   ./run_validation.sh --derived        # derived (ext) checks only
#   OUT_DIR=/somewhere ./run_validation.sh
#
# Environment (same names as import/load_core.sh):
#   BULK_DB_NAME  (default courtcase_db)
#   BULK_DB_HOST, BULK_DB_USER, BULK_DB_PASSWORD
#
# Exit status is non-zero if any check fails to run.
# =====================================================================
set -euo pipefail

DB_NAME="${BULK_DB_NAME:-courtcase_db}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PSQL_OPTS="${BULK_DB_HOST:+--host $BULK_DB_HOST} ${BULK_DB_USER:+--username $BULK_DB_USER}"
export PGPASSWORD="${BULK_DB_PASSWORD:-}"

OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/validation_report}"
mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REPORT="$OUT_DIR/validation_report.txt"

RUN_CORE=1
RUN_DERIVED=1
case "${1:-}" in
  --core)    RUN_DERIVED=0 ;;
  --derived) RUN_CORE=0 ;;
  "")        ;;
  *) echo "Unknown option: $1"; sed -n '4,16p' "$0"; exit 2 ;;
esac

run_sql () {   # run_sql <label> <file>
    local label="$1" file="$2"
    if [[ ! -f "$file" ]]; then
        echo "MISSING SCRIPT: $file" | tee -a "$REPORT"
        return 1
    fi
    {
        echo
        echo "========================================================"
        echo "== $label"
        echo "== $(basename "$file")"
        echo "========================================================"
    } | tee -a "$REPORT"
    # shellcheck disable=SC2086
    psql $PSQL_OPTS -d "$DB_NAME" -q -v ON_ERROR_STOP=1 -f "$file" 2>&1 | tee -a "$REPORT"
}

{
    echo "CourtListener research database -- validation report"
    echo "Generated : $STAMP"
    echo "Database  : $DB_NAME"
    echo "Snapshot  : CourtListener bulk data 2026-03-31"
} > "$REPORT"

# PostgreSQL has no planner statistics on the public tables after a bulk
# load, which makes the large validation joins pick bad plans. Refresh
# them first; this reads a sample, not the whole table.
if [[ "${SKIP_ANALYZE:-0}" != "1" ]]; then
    echo "Refreshing planner statistics (set SKIP_ANALYZE=1 to skip)..."
    # shellcheck disable=SC2086
    psql $PSQL_OPTS -d "$DB_NAME" -q -c "ANALYZE;"
fi

if [[ "$RUN_CORE" == "1" ]]; then
    run_sql "1. Row counts (core tables)"        "$SCRIPT_DIR/sql/01_counts.sql"
    run_sql "2. Referential integrity"           "$SCRIPT_DIR/sql/02_fk_checks.sql"
    # Note: 10_data_completeness.sql creates helper views. They are created
    # in the public schema but hold no data of their own.
    run_sql "3. Variable completeness"           "$SCRIPT_DIR/sql/10_data_completeness.sql"
fi

if [[ "$RUN_DERIVED" == "1" ]]; then
    run_sql "4. Derived layer coverage"          "$SCRIPT_DIR/deposit_pipeline/05_deposit/06_derived_coverage.sql"
fi

echo
echo "Validation report written to: $REPORT"
