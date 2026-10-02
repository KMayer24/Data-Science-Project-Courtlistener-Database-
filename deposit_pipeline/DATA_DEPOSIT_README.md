# CourtListener Research Database — data release

This package is the data deposit accompanying the CourtListener Research
Database paper. It represents the fixed CourtListener bulk-data snapshot dated
31 March 2026 and the project-created federal appellate author-attribution and
FJC case-linkage layers derived from it.

## Contents

- `public_*.csv.bz2`: CourtListener core tables, including opinion text.
- `public_search_opinion.csv.bz2.part00` .. `.part05`: the opinion table,
  split into parts because it exceeds the repository's file size limit.
- `deposit_*.csv.bz2`: publication-facing derived and reference tables.
- `release_schema.sql`: PostgreSQL table definitions generated from the
  exported relations.
- `release_indexes.sql`: primary and foreign keys applied after loading.
- `data_dictionary.tsv`: table/column/type inventory.
- `manifest.tsv`: filename, table, row count, compressed size and SHA-256.
- `SHA256SUMS`: integrity checks for all files in this package.
- `parts.tsv`: size and SHA-256 of each part of a split archive.
- `restore_deposit.sh`: loader for an empty PostgreSQL database.
- `12_validate_restored_release.sql`: publication regression checks.
- `DATA_LICENSES.md`: file-level rights and license mapping.

## Integrity check

```bash
sha256sum -c SHA256SUMS
```

`SHA256SUMS` covers the files as they are distributed, so for a split archive
it covers the individual parts. `manifest.tsv` records the digest of the whole
archive, and `restore_deposit.sh` checks that too, by hashing the concatenated
parts as a stream.

## The opinion table is split into parts

`public_search_opinion.csv.bz2` is 51.16 GB and exceeds the 50 GB per-file
limit of the hosting repository, so it is distributed as six numbered parts.
The split is at byte level, not at record level: concatenating the parts in
name order reproduces the original archive exactly, which is why the SHA-256
digest in `manifest.tsv` applies unchanged to the result.

`restore_deposit.sh` handles this by itself and needs no reassembled copy. To
rebuild the archive as a file anyway, for example for use outside this loader:

```bash
cat public_search_opinion.csv.bz2.part0[0-5] > public_search_opinion.csv.bz2
sha256sum public_search_opinion.csv.bz2   # must match the manifest entry
```

That copy needs another 51 GB of free space. If it is present, the loader uses
it and skips the parts.

## PostgreSQL restore

PostgreSQL 14 or later, `psql`, `bunzip2`, and sufficient free disk space are
required. Create an empty database and run:

```bash
createdb courtlistener_release_restore
RESTORE_DB=courtlistener_release_restore ./restore_deposit.sh
```

The loader verifies all checksums before loading, checks the restored row
count of every relation, creates primary and foreign keys, and runs the
publication regression suite. The expected attribution totals are 1,472,533
appellate opinions, 555,297 of them with a resolved author gender, of which
69,936 are female and 485,361 male. An individual judge is identified for
524,777 opinions. The expected FJC layer contains 2,403,096 normalized
appellate cases, 1,414,601 opinion links and 1,164,762 opinion-level covariate
records.

The complete package contains 50 files totalling 58.53 GB (decimal units) and
holds 35 tables. Of these, `public_search_opinion.csv.bz2` contains the
10,745,929 opinion records and occupies 51.16 GB; it is distributed as the six
`.part` files described above. The exact byte size and SHA-256 digest of every
data archive are recorded in `manifest.tsv`, and of every part in `parts.tsv`.

## Determinism

Every CSV is exported with an explicit stable ordering. The generated
`fjc_appeal_id` uses a total ordering over all normalized FJC fields; ties that
remain are identical in every exported column. The build pipeline also checks
the fixed publication totals and the previously disputed attribution for
opinion 2966699.

## Citation and code

Cite this deposit as

    Mayer, K. (2026). U.S. Judges, Judicial Careers, and Court Opinions:
    A CourtListener Database Snapshot (2026-03-31) with Opinion Authorship
    and Appellate Case Linkage (Version 1.0.0) [Dataset]. Zenodo.
    https://doi.org/10.5281/zenodo.23063945

That DOI identifies this version and these files. The DOI 10.5281/zenodo.23063944
resolves to the newest version instead, so cite the first one when the exact
snapshot matters, which is the usual case for replication.

Cite the two sources alongside it: the CourtListener bulk data published by the
Free Law Project, and the Integrated Data Base of the Federal Judicial Center.
Both are named with their URLs in the record description.

The code that produces this release, including the SQL pipeline, the export,
and the restore and validation scripts shipped here, is published at

    https://github.com/KMayer24/Data-Science-Project-Courtlistener-Database-

See `DATA_LICENSES.md` before reuse.
