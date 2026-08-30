# CourtListener Research Database

This repository documents a reduced PostgreSQL research database reconstructed
from the [CourtListener bulk-data](https://www.courtlistener.com/help/api/bulk-data/)
snapshot dated **2026-03-31**. It contains the database definition, import and
validation code, analysis queries, aggregated outputs, and figures used to
document the database.

The database structure was derived from CourtListener's accompanying
[`schema-2026-03-31.sql`](https://storage.courtlistener.com/bulk-data/schema-2026-03-31.sql).
We did not execute that schema directly. Instead, `import/schema_final.sql`
defines the reduced set of tables and the data-type and constraint adaptations
actually used in this project.

> **Data availability:** The original bulk files are not included because they
> occupy hundreds of gigabytes. The repository records the required filenames,
> snapshot date, preprocessing decisions, and final aggregate outputs.

## Repository structure

```text
import/
    schema_final.sql          Core PostgreSQL schema (17 public tables)
    load_core.sh              Core bulk-data loader
    prepare_citation_files.py Creates validated citation inputs
sql/                          Validation, descriptive, and export queries
python/                       Plotting scripts for the exported results
cleaned_csv/                  Aggregated query outputs used by the plots
figures/                      Generated figures
```

## Requirements

| Software | Requirement |
|---|---|
| PostgreSQL | 14 or later (developed with 18.6) |
| Python | 3.10 or later (developed with 3.13.5) |
| Python packages | `pandas`, `matplotlib` |
| Shell tools | `bash`, `bzcat`, `bunzip2` (`bzip2`) |

## Source data

CourtListener distributes the dated bulk-data files as `.csv.bz2` archives.
The loader expects the following local input files in `import/` by default.
Except for the FJC file, these are the decompressed CSV files. The loader
creates the two large `valid_only` citation files locally from the raw citation
exports; they are not stored in this repository.

```text
courts-2026-03-31.csv
dockets-2026-03-31.csv
opinion-clusters-2026-03-31.csv
opinions-2026-03-31.csv
citations-2026-03-31.csv
citation-map-2026-03-31.csv
people-db-people-2026-03-31.csv
people-db-races-2026-03-31.csv
people-db-schools-2026-03-31.csv
people-db-positions-2026-03-31.csv
people-db-political-affiliations-2026-03-31.csv
people-db-educations-2026-03-31.csv
people_db_race-2026-03-31.csv
search_opinioncluster_panel-2026-03-31.csv
search_opinion_joined_by-2026-03-31.csv
search_opinioncluster_non_participating_judges-2026-03-31.csv
fjc-integrated-database-2026-03-31.csv.bz2
```

After downloading the CourtListener files, decompress the CSV archives other
than the FJC file:

```bash
find import -maxdepth 1 -type f -name '*.csv.bz2' \
    ! -name 'fjc-integrated-database-*.csv.bz2' \
    -exec bunzip2 --keep {} +
```

The loader streams and normalises the compressed FJC file directly. It can
also read that file after decompression if
`fjc-integrated-database-2026-03-31.csv` is present instead.

All dated CourtListener exports came from its bulk-data snapshot. The
`fjc-integrated-database` export contains the Federal Judicial Center's
Integrated Database records distributed through CourtListener. The small
`people_db_race` lookup is an official CourtListener export containing the
eight race codes referenced by the person--race relation.

### Citation-file validation

Two raw citation exports contained references to parent records that were not
present in the same snapshot. We validated them against the loaded opinion and
opinion-cluster tables before the final import:

| Source file | Excluded rows | Reason | File used by loader |
|---|---:|---|---|
| `citation-map-2026-03-31.csv` | 2,152 | Missing `citing_opinion_id` | `citation-map-2026-03-31_valid_only.csv` |
| `citations-2026-03-31.csv` | 8 | Missing `cluster_id` | `citations-2026-03-31_valid_only.csv` |

The large `valid_only` derivatives are excluded from Git. After loading the
parent opinion and opinion-cluster tables, `load_core.sh` automatically runs
`import/prepare_citation_files.py` whenever either derivative is absent. The
script reads the parent identifiers from PostgreSQL, streams the raw citation
exports, and writes the valid rows to the two files required by the loader. It
also reproduces the excluded rows and verifies them against the small
`missing_*` files retained in `import/`.

To repeat this preparation manually after the parent tables have been loaded:

```bash
BULK_DB_NAME=courtcase_db \
BULK_DIR=/path/to/courtlistener/import \
python3 import/prepare_citation_files.py --force
```

This step processes approximately 95 million citation records and may take
some time. It uses only the Python standard library and the `psql` client.

## Database setup

### 1. Create a dedicated database

```bash
createdb -p 5432 courtcase_db
```

### 2. Apply the schema and load the data

```bash
APPLY_SCHEMA=1 bash import/load_core.sh
```

`APPLY_SCHEMA=1` drops and recreates the `public` schema. Use it only with the
dedicated project database, never with a database containing unrelated data.

The loader can be configured through environment variables:

| Variable | Default | Description |
|---|---|---|
| `BULK_DB_NAME` | `courtcase_db` | Target database |
| `BULK_DIR` | Directory containing `load_core.sh` | Local source-file directory |
| `BULK_DB_HOST` | Local PostgreSQL socket | Database host |
| `BULK_DB_USER` | Current operating-system user | Database user |
| `BULK_DB_PASSWORD` | Empty | Database password |
| `APPLY_SCHEMA` | `0` | Set to `1` to apply `schema_final.sql` |

Example with explicit paths and connection settings:

```bash
BULK_DIR=/path/to/courtlistener/import \
BULK_DB_HOST=db.example.org \
BULK_DB_USER=researcher \
BULK_DB_PASSWORD=secret \
BULK_DB_NAME=courtcase_db \
APPLY_SCHEMA=1 \
bash import/load_core.sh
```

## Schema overview

The database contains 17 tables in the `public` schema. Counts refer to the
completed 2026-03-31 import.

| Table | Rows | Description |
|---|---:|---|
| `search_court` | 3,360 | Court metadata |
| `search_docket` | 71,243,855 | Case dockets |
| `search_opinioncluster` | 10,021,372 | Case-level opinion clusters |
| `search_opinion` | 10,745,929 | Individual opinion texts |
| `search_citation` | 18,116,826 | Parsed reporter citations |
| `search_opinionscited` | 76,957,839 | Directed opinion-citation links |
| `search_opinioncluster_panel` | 834,486 | Opinion-cluster--judge panel links |
| `search_opinion_joined_by` | 1,028 | Opinion--judge join signatures |
| `search_opinioncluster_non_participating_judges` | 0 | Non-participating-judge links; source file contained only its header |
| `people_db_person` | 16,191 | Judges and other legal persons |
| `people_db_race` | 8 | Race-code lookup |
| `people_db_person_race` | 6,542 | Person--race links |
| `people_db_school` | 6,011 | Educational institutions |
| `people_db_position` | 51,291 | Judicial and professional positions |
| `people_db_politicalaffiliation` | 8,486 | Political-affiliation records |
| `people_db_education` | 12,777 | Education records |
| `recap_fjcintegrateddatabase` | 10,323,280 | FJC Integrated Database case records |

Important foreign keys include:

```text
search_opinioncluster.docket_id  -> search_docket.id
search_opinion.cluster_id        -> search_opinioncluster.id
search_opinion.author_id         -> people_db_person.id
search_docket.idb_data_id        -> recap_fjcintegrateddatabase.id
search_opinionscited.*_opinion_id -> search_opinion.id
search_citation.cluster_id       -> search_opinioncluster.id
```

## Validation

Run the core row-count and foreign-key checks after import:

```bash
psql -p 5432 -d courtcase_db -f sql/01_counts.sql
psql -p 5432 -d courtcase_db -f sql/02_fk_checks.sql
```

The completed build contained no tested foreign-key violations or duplicate
identifiers in the major court, docket, opinion, cluster, and citation tables.
The excluded citation references remain available as small diagnostic files in
`import/`.

## Analysis workflow

SQL scripts query the PostgreSQL database and write aggregated CSV files to
`cleaned_csv/`. Python scripts read these exports and generate the figures.

Example:

```bash
psql -p 5432 -d courtcase_db -f sql/04_descriptive_stats_basic_export.sql
python3 python/01_make_basic_plots.py
```

The analyses cover:

- database size and relationship integrity;
- temporal coverage of dockets, opinion clusters, and opinions;
- citation distributions and concentration;
- availability and missingness of opinion text and metadata;
- judge demographics, education, careers, and political affiliations; and
- changes in judicial appointments and court output over time.

The generated aggregate tables and plots are included so that the reported
descriptive results can be inspected without redistributing the underlying
CourtListener bulk files.

## Important limitations

- The database represents a fixed snapshot and does not include later
  CourtListener corrections or additions.
- Coverage varies substantially across courts and periods.
- Structured panel and author links are sparse for federal appellate opinions;
  free-text author and judge fields are more widely populated.
- A generated opinion cluster is not necessarily equivalent to a single
  published judicial opinion, because clusters can contain multiple opinion
  objects.
- The FJC Integrated Database primarily covers federal district-court cases and
  should not be treated as universal case metadata.

## Data licensing and attribution

This repository does not redistribute the CourtListener bulk files. Users
should obtain them from CourtListener and follow the applicable source-data
terms. CourtListener source documentation and bulk-data access are available
at <https://www.courtlistener.com/help/api/bulk-data/>. FJC Integrated Database
documentation is available from the
[Federal Judicial Center](https://www.fjc.gov/research/idb).

All other project-created files in this repository, including the database
schema, SQL, Python, and shell scripts, and this README, are available under
the [MIT License](LICENSE-CODE.md). The derived summary tables in `cleaned_csv/`
and the figures in `figures/` are available under
[CC BY 4.0](LICENSE-DATA.md). These licenses do not apply to the original
CourtListener source files.
