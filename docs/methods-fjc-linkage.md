# Linkage to FJC Appellate Case Metadata

This appendix documents the linkage between the CourtListener federal appellate corpus and the appellate component of the Federal Judicial Center's Integrated Database, summarised in the main text. The purpose of the linkage was to obtain standardised case-level information that is not consistently available in CourtListener's opinion records, including appeal type, jurisdiction, procedural disposition, and case outcome, and to construct a substantive case-domain variable.

## Source Data and Coverage

The appellate component of the FJC Integrated Database ([Integrated Data Base](https://www.fjc.gov/research/idb)) is distributed in two release files covering 1971–2007 and 2008 onward (see the codebooks listed under References). We preserved the imported raw tables as compressed CSV snapshots and harmonised the fields shared across the two releases. The resulting table contains 2,403,096 appellate records and includes the FJC circuit code, docket number, docket and judgment dates, appeal type, originating agency, jurisdiction, nature of suit, nature of offence, appellant, appellee, outcome, disposition, and statistical year.

The appellate IDB covers cases from Statistical Year 1971 onwards. CourtListener opinions filed before 1971 therefore fall outside the linkage period. The U.S. Court of Appeals for the Federal Circuit is also excluded because the two appellate IDB files do not provide a separate circuit code for that court.

Existing FJC links in the CourtListener data were available for district-court cases but not for appellate opinions, consistent with the Free Law Project's description of its initial integration of the civil IDB component (see References). We therefore constructed a separate opinion-level linkage between the CourtListener appellate corpus and the FJC appellate files.

## Court-Code Harmonisation

The FJC and CourtListener use different court identifiers. We therefore constructed a deterministic crosswalk between the FJC circuit codes and the CourtListener courts included in the linkage. All 2,403,096 retained FJC records received a valid CourtListener court identifier. The court crosswalk was used both to restrict candidate matches to the same appellate court and to prevent identical docket numbers from different circuits from being treated as potential matches.

**Table 1.** Crosswalk between FJC circuit codes and CourtListener courts.

| FJC | CourtListener | Court |
|---|---|---|
| 0 | cadc | D.C. Circuit |
| 1 | ca1 | First Circuit |
| 2 | ca2 | Second Circuit |
| 3 | ca3 | Third Circuit |
| 4 | ca4 | Fourth Circuit |
| 5 | ca5 | Fifth Circuit |
| 6 | ca6 | Sixth Circuit |
| 7 | ca7 | Seventh Circuit |
| 8 | ca8 | Eighth Circuit |
| 9 | ca9 | Ninth Circuit |
| 10 | ca10 | Tenth Circuit |
| 11 | ca11 | Eleventh Circuit |

## Docket-Number Normalisation

Docket numbers are formatted inconsistently within and across the two sources. The FJC files store the matchable component as a compact combination of filing year and sequence number, whereas CourtListener retains the displayed docket string. We therefore converted CourtListener docket numbers to a common seven-digit key consisting of a two-digit year followed by a five-digit, zero-padded sequence number.

The normalisation recognised two principal structures:

1. A leading appellate docket number, optionally preceded by *No.*, as in *05-71379* or *13-4156-cr*
2. A docket number introduced by the word *Docket*, as in *1163, Docket 80-1065*, *No. 809, Docket 78-1028*, or *Docket No. 02-7708*

For example, the displayed docket number *80-1065* was transformed into the common key *8001065*. Alphabetic suffixes and surrounding descriptive material were not used in the key.

The second parsing rule was particularly important for historical Second Circuit opinions, in which a running case number often precedes the appellate docket number. It recovered 20,231 additional CourtListener opinions in that circuit.

Within the IDB-covered period from 1971 onward, docket numbers were successfully normalised for 1,175,011 of 1,223,958 opinions (96.00%). Parseability exceeded 95% in ten of the twelve circuits, with lower rates in the Second Circuit (86.83%) and the D.C. Circuit (85.70%), where historical docket-number conventions were less uniform (Table 2). Opinions without a successfully normalised docket number were excluded from candidate generation.

**Table 2.** Docket-number parseability within the IDB-covered period, by circuit.

| Circuit | Opinions | Normalised | Share (%) |
|---|---:|---:|---:|
| First | 37,926 | 36,961 | 97.46 |
| Second | 89,525 | 77,736 | 86.83 |
| Third | 87,461 | 84,200 | 96.27 |
| Fourth | 168,018 | 164,855 | 98.12 |
| Fifth | 181,757 | 177,293 | 97.54 |
| Sixth | 94,925 | 92,022 | 96.94 |
| Seventh | 79,423 | 76,909 | 96.83 |
| Eighth | 88,017 | 85,241 | 96.85 |
| Ninth | 206,523 | 196,978 | 95.38 |
| Tenth | 61,919 | 60,044 | 96.97 |
| Eleventh | 94,789 | 93,912 | 99.07 |
| D.C. | 33,675 | 28,860 | 85.70 |
| **Total** | **1,223,958** | **1,175,011** | **96.00** |

## Candidate Generation

We generated candidate matches by joining CourtListener opinions to FJC records on the appellate court and normalised docket number. Thus, each candidate came from the same court and had the same docket-number key as the corresponding CourtListener opinion.

We retained all matching FJC records rather than selecting one record per docket at this stage. A docket number can be associated with multiple records, for example because of reopened proceedings or successive procedural stages. Premature deduplication could therefore remove the record corresponding to the CourtListener opinion. Cases with multiple candidates were resolved in the subsequent matching stage.

## Candidate Selection and Linkage Results

We linked CourtListener opinions to FJC records that shared the same appellate court and normalised docket number. When several FJC records met these criteria, we selected the record whose judgment date was closest to the CourtListener opinion date. We resolved any remaining ties using the FJC record identifier.

We included a selected link in the analysis only when the dates matched exactly or differed by no more than seven days. We retained links with larger differences for diagnostic purposes but excluded them from the analysis because they could represent a different proceeding associated with the same docket.

We performed the linkage separately for each CourtListener opinion object. Majority, concurring, and dissenting opinions from the same decision generally shared the same court, docket number, and filing date and therefore received the same FJC record. We treated the linked metadata as describing the underlying appeal rather than separate cases for each opinion type.

**Table 3.** Linkage outcomes and analytical eligibility.

| Linkage outcome | Opinions | Share (%) | Analysis |
|---|---:|---:|---|
| *FJC record selected* | | | |
| Exact date agreement | 1,033,696 | 73.07 | Included |
| Date difference of 1–7 days | 35,449 | 2.51 | Included |
| Date difference of 8–30 days | 19,609 | 1.39 | Excluded |
| Date difference greater than 30 days | 76,008 | 5.37 | Excluded |
| *No FJC record selected* | | | |
| No record with the same court and docket | 11,207 | 0.79 | Excluded |
| Docket number not normalisable | 238,632 | 16.87 | Excluded |
| **All examined opinions** | **1,414,601** | **100.00** | |

*Note.* The outcome categories are mutually exclusive. Exact date matches and differences of no more than seven days were admitted to the analysis. Shares use all examined opinions as the denominator.

Table 3 includes all 1,414,601 examined opinions, including those filed before the appellate IDB coverage began in 1971. Of the 238,632 opinions without a normalisable docket number, 189,685 were from this earlier period. Within the coverage period, 48,947 opinions lacked a normalisable docket number, consistent with Table 2. Overall, 1,069,145 opinions (75.58%) satisfied the linkage criteria and were admitted to the analysis.

Among the 1,069,145 admissible links, 96.68% had identical CourtListener and FJC dates, and 98.30% differed by no more than one day. Because we used date proximity for candidate selection and analytical eligibility, we interpret this agreement as descriptive evidence of temporal plausibility rather than as an independent estimate of linkage accuracy. The requirement that candidates share both the appellate court and normalised docket number provided an additional safeguard against false matches.

Linkage coverage varied across circuits because CourtListener docket numbers differed in availability and formatting. As Table 2 shows, most of this variation within the IDB coverage period occurred in the Second and D.C. Circuits.

## Construction of Case-Level Variables

For each admitted FJC record, we retained the appeal type, nature of suit, nature of offence, originating agency, jurisdiction code, appellant, appellee, outcome, and disposition. Following the appellate IDB codebooks, we used the FJC appeal type to assign each record to a broad procedural class and to determine which field was relevant for the case-domain classification (see the codebooks listed under References). Table 4 summarises this routing.

**Table 4.** Routing of FJC appeal types to case-domain information.

| Procedural class | FJC appeal types | Field used for classification |
|---|---|---|
| Administrative | 1–2 | Originating agency |
| Civil | 3, 4, and 7 | Nature of suit |
| Criminal | 5, 8, and 13–21 | Nature of offence |
| Original proceeding | 6 | Residual domain |
| Bankruptcy | 9–12 | Residual domain |
| Other or miscellaneous | 22 or unclassified | Residual domain |

### Case Domains

We mapped the routed FJC information to six case domains. We assigned criminal appeals to the immigration domain when the FJC offence code identified an immigration offence and classified the remaining direct criminal appeals as criminal. For administrative appeals, we used the originating agency to identify immigration, employment, and benefits cases. For civil appeals, we used the FJC nature-of-suit code. We assigned all remaining records to the other domain. The complete code-level crosswalk is included in the replication materials. Table 5 presents the resulting distribution among admissible FJC links.

**Table 5.** Substantive case domains among admissible FJC links.

| Domain | Opinions | Share (%) |
|---|---:|---:|
| Other | 387,472 | 36.2 |
| Criminal | 270,781 | 25.3 |
| Civil rights | 175,635 | 16.4 |
| Immigration | 110,719 | 10.4 |
| Employment | 93,646 | 8.8 |
| Benefits | 30,892 | 2.9 |
| **Total** | **1,069,145** | **100.0** |

### Outcome Classification

We used the FJC outcome variable to classify how the court of appeals treated the decision under review. Table 6 presents the resulting outcome classes, their corresponding FJC categories, and their distribution among admissible links.

**Table 6.** Classification and distribution of FJC appellate outcomes.

| Outcome class | FJC results included | Opinions | Share (%) |
|---|---|---:|---:|
| Affirmed | Affirmed or enforced | 739,044 | 69.1 |
| Reversed | Reversed or vacated; remanded | 149,716 | 14.0 |
| Mixed | Affirmed in part and reversed in part | 58,298 | 5.5 |
| Other | Dismissed; other merits decisions; certificate of appealability denied; other or unmapped results | 77,351 | 7.2 |
| Missing | FJC missing-value code (`-8`) | 44,736 | 4.2 |
| **Total** | | **1,069,145** | **100.0** |

*Note.* Shares use all admissible opinion-level links as the denominator. Multiple CourtListener opinion objects from the same appeal may carry the same FJC outcome.

The reversed class comprised 130,950 records coded as reversed or vacated and 18,766 coded as remanded. The other class combined dismissed, other-merits, certificate-denied, and unmapped results.

Because the FJC revised its outcome coding beginning in Statistical Year 1985, some earlier values do not have directly comparable later definitions. We conservatively assigned values without a clear analytical equivalent to the other class.

## Dependence Structure and Limitations

The linkage unit was the individual CourtListener opinion object, whereas the FJC variables describe the underlying appeal. Among the 1,069,145 admissible links, 760,199 opinion objects (71.1%) were the only linked opinion associated with their FJC appeal, while 308,946 (28.9%) shared an appeal with at least one additional opinion object. Majority, concurring, and dissenting opinions from the same decision could therefore inherit the same case domain and outcome. We treated these variables as appeal-level metadata and did not interpret repeated opinion objects as independent case-level observations.

The linkage is limited to the period covered by the appellate IDB and excludes the Federal Circuit. It also depends on the availability and normalisation of CourtListener docket numbers, which varied particularly in the Second and D.C. Circuits (Table 2). When several FJC records shared the same court and docket number, selecting the temporally closest record reduced but could not eliminate the possibility of matching a different procedural stage. Moreover, because date proximity informed both candidate selection and analytical eligibility, date agreement does not constitute an independent validation of linkage accuracy.

## Implementation

| Stage | Script |
|---|---|
| Raw FJC appellate import | [`10_create_fjc_appellate_raw_tables.sql`](../deposit_pipeline/04_case_metadata/10_create_fjc_appellate_raw_tables.sql) |
| Harmonisation and court crosswalk | [`11_create_fjc_appellate_normalized.sql`](../deposit_pipeline/04_case_metadata/11_create_fjc_appellate_normalized.sql) |
| Docket normalisation, candidate selection | [`19_build_fjc_opinion_matches.sql`](../deposit_pipeline/04_case_metadata/19_build_fjc_opinion_matches.sql) |
| Domain, outcome and disposition crosswalks | [`20_fjc_code_crosswalks.sql`](../deposit_pipeline/04_case_metadata/20_fjc_code_crosswalks.sql) |
| Opinion-level covariates | [`21_materialize_opinion_covariates.sql`](../deposit_pipeline/04_case_metadata/21_materialize_opinion_covariates.sql) |

## References

- Federal Judicial Center. *Integrated Data Base*, appeals component. <https://www.fjc.gov/research/idb>
- Federal Judicial Center. *Codebook, Appeals Integrated Data Base, 1971–2007*. Distributed with the IDB appeals files.
- Federal Judicial Center. *Codebook, Appeals Integrated Data Base, 2008 onward*. Distributed with the IDB appeals files.
- Free Law Project. Integration of the FJC civil Integrated Data Base component into CourtListener.
