# Deposit pipeline

The SQL that builds the derived layer of the CourtListener research
database, assembled here so that the data paper's deposit is reproducible
from one place.

## Scope

This folder is the canonical preprocessing pipeline for the data-paper
release. It contains corpus selection, judge references, author attribution,
FJC case linkage, and the deposit-facing derived layer. Expected release
counts and deterministic-key checks are enforced by the rebuild command.

## Two databases

| | |
|---|---|
| `courtcase_db`, shared cluster, port 5432 | Source research database. Read-only. |
| `courtlistener_deposit`, own instance, port 5435 | The submission database. Everything the paper deposits is built here. |

The submission database runs in its own PostgreSQL instance under
`/data/workspace/kmayer/pg_deposit`, because the shared cluster grants no
`CREATEDB`. Separate process, separate files, separate port — the two
cannot contaminate each other.

```bash
# start (it does not survive a reboot)
/usr/lib/postgresql/18/bin/pg_ctl -D /data/workspace/kmayer/pg_deposit \
  -l /data/workspace/kmayer/pg_deposit/server.log \
  -o "-p 5435 -k /data/workspace/kmayer/pg_deposit" start

# connect
psql -h /data/workspace/kmayer/pg_deposit -p 5435 -d courtlistener_deposit
```

## Stages

| Folder | What it builds |
|---|---|
| `01_corpus_selection/` | The 13 federal appellate courts and the 1,472,533-opinion corpus |
| `02_judge_reference/` | FJC judge biographies, service records, court-name crosswalk, supplemental judges |
| `03_gender_assignment/` | The four-stage author attribution cascade |
| `04_case_metadata/` | FJC appellate records, opinion↔case linkage, crosswalks |
| `05_deposit/` | Person-level attribution, party variables, the `deposit` schema, validation |

## Building the submission database

```bash
./build_deposit_db.sh --all     # from the repository root
```

By default this copies the validated `ext_release` outputs into schema `ext`,
copies the CourtListener core tables into `public`, then runs the
`05_deposit/` scripts to produce the `deposit` schema.

### Delivering the data is not the same as rebuilding it

Stages 01–04 are **not** re-executed during this build. Their validated
outputs are copied from the source research database, so the submission
database can be exported without the full text table.

**A rebuild from scratch requires the full CourtListener snapshot,
including `public.search_opinion`.** Verified against the scripts:

- `03_gender_assignment/08` (stages 3 and 4) reads `public.search_opinion`
  directly. It needs `xml_harvard` for the XML `<author>` element and
  `html_with_citations` for the attribution formula. `xml_harvard` is not
  carried in `ext.federal_appeal_opinions` at all, so no metadata table
  can stand in for it.
- `01_corpus_selection/02` builds the corpus from `public.search_opinion`,
  `public.search_docket` and `public.search_opinioncluster`.

The submission database deliberately omits that 160 GB table (see the
table below), which means:

| | |
|---|---|
| Deliver the data | Works from the submission database as it is. |
| Rebuild the derived layer | Needs the full snapshot including opinions. Load it with `./build_deposit_db.sh --opinion-text`, or rebuild against a database loaded from the bulk files. |

Rebuilding takes several hours; stage `03_gender_assignment/08` alone ran
for 1 h 23 min on the original pass.

### Reproducing the publication release

Run the complete stages 01–04 in an isolated schema:

```bash
./rebuild_publication_pipeline.sh --target ext_release
```

The command never writes to `public` or the source `ext` schema. It recomputes
the corpus and derived tables, then fails unless the publication release has
exactly 1,472,533 appellate opinions and a resolved author gender for 555,297
of them, of which 69,936 are female and 485,361 male. Pass `--replace` only
when intentionally replacing an existing release schema. For a faster repeat
of only the gender stage, use `--gender-only`; this copies the already-verified
corpus and judge-reference inputs before rebuilding all four gender-assignment
steps.

The author-attribution rule treats a literal `Before:` line as the start of a
five-line panel-header block. Recorded author gender is resolved for 555,297
opinions. A single judge is identified for 524,777 of those opinions; only
that group supports judge-level analysis. These totals are regression-tested
by the rebuild and deposit-validation commands.

The release also makes the generated FJC appellate identifier reproducible.
The five-field natural key contains 208 tied groups (419 rows), so ordering
only by those fields would leave IDs dependent on executor order. Step 04/11
uses all normalised FJC fields as a total ordering. Two clean builds from
physically different copies of the same raw tables produced zero bidirectional
row differences in `fjc_appellate_normalized`, `fjc_opinion_match`, and
`opinion_fjc_covariates`. The rebuild command additionally rejects any FJC ID
that does not follow this canonical ordering.

### Proof that these scripts produce those tables

Copying the tables shows what they contain, not that this pipeline produces
them. The proof comes from `../rebuild_publication_pipeline.sh`, which runs
stages 01–04 into a fresh schema, asserts the publication totals, validates the
author-attribution output, and enforces the canonical FJC identifier order.

## The 05_deposit scripts

| Script | Purpose |
|---|---|
| `01_unique_person_attribution.sql` | Flags attributions that identify exactly one judge (524,777 of 555,297) and resolves the judge identifier back to its registry |
| `02_unique_person_attribution_export.sql` | Summary CSVs and the per-opinion export |
| `03_validation_sample.sql` | 200-opinion manual validation sample, stratified by step, deterministic draw |
| `04_author_party_resolved.sql` | Reconstruction of the lost build script for `ext.author_party_resolved` |
| `05_verify_author_party_resolved.sql` | Proves the reconstruction reproduces the original exactly (0 mismatches) |
| `06_derived_coverage.sql` | Coverage and integrity checks for the derived layer |
| `07_deposit_views.sql` | The `deposit` schema: neutral names, intermediates omitted |
| `08_author_party_timeaware.sql` | Corrected party variable: the two measures separated, affiliation resolved at the filing date |
| `09_federal_appeals_recap_split_check.sql` | Audits the RECAP/provenance split used in the coverage figure |
| `10_author_id_conflict_check.sql` | Measures conflicts between structured `author_id` and free-text `author_str` |
| `11_guard_cause_test.sql` | Preserves the diagnostic that identified the over-restrictive five-line guard |

`03_validation_sample.sql` needs `ext.federal_appeal_opinions` for the text
excerpts and therefore runs against the source research database, not the
submission database, which does not carry the 17 GB text table. Its output is
exported to `export/deposit/`.

## What the submission database deliberately leaves out

| Not copied | Why |
|---|---|
| `public.search_opinion` | 160 GB. Deposit record B, pending the Zenodo/GESIS decision. Add with `--opinion-text`. |
| `ext.federal_appeal_opinions` | 17 GB of opinion text, duplicated from `public.search_opinion`. The metadata twin is deposited. |
| `ext.federal_appeals_opinion_header_text` | Materialised view with no build script. |
| `ext.opinion_legal_domain` | No build script, and 42 % of rows carry neither domain nor source. |
| `ext.author_gender_author_id`, `ext.author_gender_author_str_fjc` | Superseded stage tables; nothing is rebuilt from them. |
| `ext.author_party_resolved` | Copied as a build input, but not deposited: it merges two different party concepts and dates the affiliation by last record rather than by filing date. `08` supersedes it. |

## Release provenance

The SQL files in stages 01–05 are the authoritative code for this release.
Working logs and exploratory or deprecated scripts are not part of the
deposit. Rebuilds must use the versioned files in this folder and pass the
regression checks before export.
