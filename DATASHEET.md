# Datasheet for the CourtListener Research Database

This document follows the questions proposed in
[Datasheets for Datasets](https://doi.org/10.1145/3458723). It describes the
fixed dataset version archived at <https://doi.org/10.5281/zenodo.23063945>.
Technical instructions for building and restoring the database remain in the
[repository README](README.md).

## Motivation

### Why was the dataset created?

I created the database to provide a manageable relational resource for
research on American judges, judicial careers, court opinions, citations, and
panel composition. The complete CourtListener bulk release is large and its
structured author information is sparse for federal appellate opinions. The
database therefore combines a reduced set of CourtListener tables with a
derived layer for opinion-author attribution and linkage to Federal Judicial
Center (FJC) appellate case records.

### Who created and funded it?

Katharina Mayer created the database at the University of Konstanz. No
separate external funding was reported for this release.

## Composition

### What does the dataset contain?

The release contains 35 relational tables: 17 selected CourtListener source
tables and 18 deposit-facing reference, crosswalk, and derived tables. The
core tables describe courts, dockets, opinion clusters, individual opinions,
citations, panel relationships, persons, positions, education, race,
political affiliations, and FJC district-court records. The derived layer
contains:

- the 13 federal courts of appeals and 1,472,533 associated opinions;
- judge biographies, service records, a court-name crosswalk, and eight
  supplemental judge records;
- author-attribution results and diagnostics for every appellate opinion;
- 2,403,096 harmonised FJC appellate case records;
- opinion-to-FJC candidate links and derived case covariates; and
- crosswalks for case domain, disposition, and outcome.

The release also provides a PostgreSQL schema, indexes, a column-level data
dictionary, manifests, checksums, a restore script, and release-validation
queries. Exact row counts and file hashes are recorded in `manifest.tsv` in
the Zenodo package.

### What does each instance represent?

The unit varies by table. An instance may represent a court, docket, opinion
cluster, opinion, citation, person, position, educational record, panel
relationship, FJC proceeding, author attribution, or opinion-to-case link.
Keys and foreign keys preserve the relationships among these units. An
opinion is not interchangeable with an opinion cluster or an FJC proceeding,
and several opinions may be linked to one proceeding.

### Is this a sample?

The 17 core tables are selected tables from the complete CourtListener
snapshot, not a statistical sample of their rows. The federal appellate
derived layer includes every opinion assigned to the 13 explicitly selected
federal courts of appeals in that snapshot. The separate manual-validation
dataset in [`validation/`](validation/) is a deterministic stratified sample
of 200 author attributions and is not part of the published Zenodo package.

### Are data missing or incomplete?

Yes. Missingness varies across variables, courts, persons, and periods.
CourtListener coverage is not a census of judicial output. Older decisions
are less completely represented, and the growth of RECAP affects recent
federal district-court coverage. Structured author identifiers are present
for only 0.7% of the federal appellate corpus. The derived procedure resolves
recorded author gender for 555,297 opinions (37.7%) and identifies one judge
for 524,777 opinions.

The FJC appellate files begin in 1971 and do not cover the Federal Circuit.
Among the 1,414,601 opinions in the twelve linkable circuits, 1,069,145 have
an admissible FJC link with exact date agreement or a date difference of no
more than seven days.

### Are there known errors or exclusions?

The source citation-map file contained 2,152 rows whose citing opinion was
absent from the snapshot, and the citation file contained eight rows whose
opinion cluster was absent. I excluded those rows from the relational import
and retained them as diagnostic files in the repository.

Manual validation of 200 person-level author attributions found 196 correct
and four incorrect assignments. All four errors came from CourtListener's
structured `author_id` field; none in the sample was introduced by the name
extraction or matching steps. The published Zenodo version is fixed and has
not been altered after this audit. The annotated sample and step-specific
precision estimates are documented in [`validation/README.md`](validation/README.md).

### Does the dataset contain confidential or sensitive information?

The data are derived from public court records and public biographical
sources. They contain names and recorded demographic or political attributes
of public officials, including gender, race, religion, and political
affiliation where present in the source. They contain no information that I
collected directly from individuals. I did not infer demographic attributes
from names or opinion text. The recorded categories may not reflect
self-identification and should not be treated as such.

## Collection process

### How were the source data obtained?

I used the CourtListener bulk-data release dated 31 March 2026. The FJC
components consist of records distributed through CourtListener and the two
public appellate Integrated Database releases covering 1971--2007 and 2008
onwards. The repository records the required filenames and the source URLs.
No web scraping, participant recruitment, or direct data collection was used.

### Over what period were the data collected?

The snapshot was released on 31 March 2026 and contains historical records
from varying periods. The appellate FJC case files begin in 1971. Dates in
the database describe the underlying courts, persons, opinions, and cases;
they do not indicate when I collected each individual record.

### Was consent obtained?

No consent procedure was used because the dataset reuses public records about
public officials and public judicial proceedings. Researchers must still
consider the consequences of combining and analysing personal attributes,
especially when reporting small groups or individual-level results.

## Preprocessing, cleaning, and labelling

### What preprocessing was performed?

I adapted CourtListener's published schema to the selected tables and retained
the original identifiers. I validated data types, primary keys, row counts,
and foreign-key relationships; removed the unmatched citation rows described
above; and kept the exclusions as diagnostics.

For the federal appellate layer, I:

1. selected courts by explicit CourtListener court identifier;
2. combined CourtListener and FJC biographical and service records into a
   judge reference set;
3. attributed opinions through a four-step cascade using a structured author
   link, the recorded author name, an XML author element, and an HTML
   attribution formula;
4. accepted a name match only when all candidates in the best available tier
   agreed on the reported result;
5. harmonised the two FJC appellate releases and assigned deterministic
   internal identifiers; and
6. linked opinions to FJC proceedings using a court crosswalk, a normalised
   docket key, and the closest judgment date, retaining date distance as a
   match diagnostic.

The source tables remain unchanged by the derived pipeline. Derived tables
and diagnostics are stored separately. Full methodological details are in
[`docs/methods-authorship.md`](docs/methods-authorship.md) and
[`docs/methods-fjc-linkage.md`](docs/methods-fjc-linkage.md).

### Was automated inference used?

Rules and relational matching were used for author attribution and case
linkage. No machine-learning model was trained. Gender was inherited from the
matched biographical record; it was not inferred from a name or from opinion
text. Eight supplemental judge records were manually verified. A separate
manual audit evaluated the final person-level author attribution.

### Can the processing be reproduced?

Yes. The SQL, Python, and shell scripts are versioned in this repository. The
Zenodo package includes the schema, data dictionary, checksums, restore
script, and validation queries. The repository README gives the complete
build, export, restore, and validation commands. Reproduction requires
PostgreSQL 14 or later and substantial storage and processing capacity.

## Uses

### What uses are supported?

The database supports descriptive, relational, network-based, and text-based
research on courts, judicial careers, panel composition, opinion authorship,
citations, case characteristics, outcomes, and legal language. Users can
analyse only the core source tables or join them to the derived appellate
layer.

### What uses require caution or are unsuitable?

Counts must be interpreted as coverage of the snapshot, not complete judicial
output. The data should not be used as a current court docket, an authoritative
legal record, or a substitute for checking an official opinion. Missingness
may be systematic across courts, periods, and personal characteristics.
Author attribution and FJC linkage are derived and retain uncertainty even
where a match is admissible. Only the 524,777 opinions with a unique person
identifier support individual-judge analyses.

Researchers should not interpret recorded demographic categories as
self-identification or use them to make decisions about individuals. Any
analysis involving protected or sensitive attributes should report coverage,
missingness, and the relevant denominator.

### Are there comparable datasets?

Related resources include CourtListener, the FJC Integrated Database, the
Supreme Court Database, the U.S. Courts of Appeals Database, the Caselaw
Access Project, and the Pile of Law. They differ in court coverage, time
period, unit of analysis, text availability, and biographical information.

## Distribution

### How is the dataset distributed?

The fixed release is openly available on Zenodo:

> Mayer, K. (2026). *U.S. Judges, Judicial Careers, and Court Opinions: A
> CourtListener Database Snapshot (2026-03-31) with Opinion Authorship and
> Appellate Case Linkage* (Version 1.0.0) [Dataset]. Zenodo.
> <https://doi.org/10.5281/zenodo.23063945>

The package contains bzip2-compressed CSV files. The largest archive is split
into numbered byte-level parts; the supplied restore script reads these parts
as one stream. The full package contains 50 files totalling 58.53 GB.

### What licenses and rights statements apply?

CourtListener and FJC source tables carry the Creative Commons Public Domain
Mark 1.0 used by CourtListener. Project-created derived data are licensed
under CC BY 4.0. Code and project-authored technical documentation are
licensed under the MIT License. The file-level mapping is documented in
[`DATA_LICENSES.md`](DATA_LICENSES.md).

### Are there access restrictions?

No registration or application is required. Users need sufficient local
storage and software to download and restore the complete release. The GitHub
repository does not duplicate the large source and release files.

## Maintenance

### Will the dataset be updated?

The DOI above identifies a fixed version of the 31 March 2026 snapshot. It
will not be changed in place. If I publish a later snapshot or a corrected
release, it will receive a new version and its changes will be documented.
The GitHub repository may continue to receive code, documentation, and audit
updates that postdate the fixed Zenodo version.

### How can errors be reported?

Errors and documentation questions can be reported through the repository's
[GitHub issue tracker](https://github.com/KMayer24/Data-Science-Project-Courtlistener-Database-/issues).
Reports should identify the dataset version, table, and relevant record
identifier without reproducing unnecessary personal information.
