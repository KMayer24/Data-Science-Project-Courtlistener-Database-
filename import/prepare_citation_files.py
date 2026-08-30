#!/usr/bin/env python3
"""Create referentially valid citation CSV files for the database loader.

The parent opinion and opinion-cluster tables must already be loaded. The
script reads their identifiers through psql, streams the two raw CourtListener
citation exports, and separates valid rows from rows with missing references.
"""

from __future__ import annotations

import argparse
import csv
import os
from pathlib import Path
import subprocess
import sys
from typing import Callable


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Recreate valid_only files even when they already exist.",
    )
    return parser.parse_args()


def psql_command() -> list[str]:
    command = [
        "psql",
        "--no-psqlrc",
        "--quiet",
        "--set",
        "ON_ERROR_STOP=1",
        "--dbname",
        os.environ.get("BULK_DB_NAME", "courtcase_db"),
    ]
    host = os.environ.get("BULK_DB_HOST")
    user = os.environ.get("BULK_DB_USER")
    if host:
        command.extend(["--host", host])
    if user:
        command.extend(["--username", user])
    return command


def load_identifier_bitmap(table: str) -> tuple[bytearray, int]:
    """Read non-negative integer IDs from PostgreSQL into a compact bitmap."""
    query = f"COPY (SELECT id FROM public.{table}) TO STDOUT"
    process = subprocess.Popen(
        [*psql_command(), "--command", query],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    assert process.stdout is not None
    assert process.stderr is not None

    bitmap = bytearray()
    count = 0
    for line in process.stdout:
        value_text = line.strip()
        if not value_text:
            continue
        try:
            value = int(value_text)
        except ValueError as error:
            process.kill()
            raise RuntimeError(
                f"Unexpected identifier returned for {table}: {value_text!r}"
            ) from error
        if value < 0:
            process.kill()
            raise RuntimeError(f"Negative identifier returned for {table}: {value}")
        if value >= len(bitmap):
            bitmap.extend(b"\0" * (value + 1 - len(bitmap)))
        bitmap[value] = 1
        count += 1

    stderr = process.stderr.read()
    return_code = process.wait()
    if return_code:
        raise RuntimeError(
            f"Could not read identifiers from {table} via psql:\n{stderr.strip()}"
        )
    print(f"Loaded {count:,} identifiers from {table}.")
    return bitmap, count


def reference_exists(value: str | None, bitmap: bytearray) -> bool:
    """Treat NULL references as valid because the schema permits them."""
    if value is None or value == "":
        return True
    try:
        identifier = int(value)
    except ValueError:
        return False
    return 0 <= identifier < len(bitmap) and bool(bitmap[identifier])


def read_rows_by_id(path: Path) -> tuple[list[str], dict[str, tuple[str, ...]]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle, escapechar="\\")
        try:
            header = next(reader)
        except StopIteration as error:
            raise RuntimeError(f"CSV file is empty: {path}") from error
        try:
            id_index = header.index("id")
        except ValueError as error:
            raise RuntimeError(f"CSV file has no id column: {path}") from error
        rows: dict[str, tuple[str, ...]] = {}
        for row in reader:
            row_id = row[id_index]
            if row_id in rows:
                raise RuntimeError(f"Duplicate id {row_id} in {path}")
            rows[row_id] = tuple(row)
    return header, rows


def split_csv(
    source: Path,
    valid_output: Path,
    missing_output: Path,
    row_is_valid: Callable[[dict[str, str]], bool],
) -> tuple[int, int]:
    if not source.exists():
        raise FileNotFoundError(f"Required raw source file is missing: {source}")

    valid_temporary = valid_output.with_name(valid_output.name + ".tmp")
    missing_temporary = missing_output.with_name(missing_output.name + ".tmp")
    valid_count = 0
    missing_count = 0

    try:
        with (
            source.open("r", encoding="utf-8", newline="") as source_handle,
            valid_temporary.open("w", encoding="utf-8", newline="") as valid_handle,
            missing_temporary.open("w", encoding="utf-8", newline="") as missing_handle,
        ):
            reader = csv.DictReader(source_handle, escapechar="\\")
            if reader.fieldnames is None:
                raise RuntimeError(f"CSV file has no header: {source}")
            valid_writer = csv.DictWriter(
                valid_handle,
                fieldnames=reader.fieldnames,
                extrasaction="raise",
                lineterminator="\n",
            )
            missing_writer = csv.DictWriter(
                missing_handle,
                fieldnames=reader.fieldnames,
                extrasaction="raise",
                lineterminator="\n",
            )
            valid_writer.writeheader()
            missing_writer.writeheader()

            for row in reader:
                if row_is_valid(row):
                    valid_writer.writerow(row)
                    valid_count += 1
                else:
                    missing_writer.writerow(row)
                    missing_count += 1

        if missing_output.exists():
            expected_header, expected_rows = read_rows_by_id(missing_output)
            actual_header, actual_rows = read_rows_by_id(missing_temporary)
            if expected_header != actual_header or expected_rows != actual_rows:
                expected_ids = set(expected_rows)
                actual_ids = set(actual_rows)
                raise RuntimeError(
                    f"Generated exclusions for {source.name} do not match "
                    f"{missing_output.name}. "
                    f"Only expected: {len(expected_ids - actual_ids):,}; "
                    f"only generated: {len(actual_ids - expected_ids):,}."
                )
            missing_temporary.unlink()
        else:
            missing_temporary.replace(missing_output)

        valid_temporary.replace(valid_output)
    except Exception:
        valid_temporary.unlink(missing_ok=True)
        missing_temporary.unlink(missing_ok=True)
        raise

    print(
        f"Prepared {valid_output.name}: {valid_count:,} valid rows; "
        f"{missing_count:,} excluded rows."
    )
    return valid_count, missing_count


def main() -> int:
    args = parse_args()
    base = Path(os.environ.get("BULK_DIR", Path(__file__).resolve().parent))

    citation_map_valid = base / "citation-map-2026-03-31_valid_only.csv"
    citations_valid = base / "citations-2026-03-31_valid_only.csv"
    prepare_map = args.force or not citation_map_valid.exists()
    prepare_citations = args.force or not citations_valid.exists()
    if not prepare_map and not prepare_citations:
        print("Both valid_only citation files already exist; nothing to do.")
        return 0

    opinion_ids: bytearray | None = None
    cluster_ids: bytearray | None = None
    if prepare_map:
        opinion_ids, _ = load_identifier_bitmap("search_opinion")
    if prepare_citations:
        cluster_ids, _ = load_identifier_bitmap("search_opinioncluster")

    if prepare_map:
        assert opinion_ids is not None
        split_csv(
            base / "citation-map-2026-03-31.csv",
            citation_map_valid,
            base / "citation-map-2026-03-31_missing_citing.csv",
            lambda row: reference_exists(row.get("cited_opinion_id"), opinion_ids)
            and reference_exists(row.get("citing_opinion_id"), opinion_ids),
        )

    if prepare_citations:
        assert cluster_ids is not None
        split_csv(
            base / "citations-2026-03-31.csv",
            citations_valid,
            base / "citations-2026-03-31_missing_cluster.csv",
            lambda row: reference_exists(row.get("cluster_id"), cluster_ids),
        )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
