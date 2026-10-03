# Author-Gender Assignment Details

This appendix documents the judge reference data, name-matching hierarchies, and source-based attribution rules used in the sequential author-gender assignment described in the main text. The four steps resolved 10,234, 408,245, 11,514, and 125,304 additional opinions, respectively. Because each step considered only opinions that remained unresolved after the preceding steps, these counts are mutually exclusive.

## Judge Reference Set

We constructed the judge reference set from CourtListener person and position records and the Federal Judicial Center's *Biographical Directory of Article III Federal Judges* ([Biographical Directory of Article III Federal Judges](https://www.fjc.gov/history/judges)). From the category-organized relational export, downloaded on May 11, 2026, we used the individual *Demographics* and *Federal Judicial Service* CSV files. The first provides judge identifiers, name components, and recorded gender, while the second provides judicial appointments and court-service periods.

We linked the files through the common FJC judge identifier, retained service on the U.S. Courts of Appeals, and mapped the FJC court names to the thirteen CourtListener courts included in the corpus. Because the FJC export changes over time, the retrieval date identifies the version used in this study. We retained local copies of both source files and recorded their SHA-256 checksums in the replication materials.

The FJC integration added 129 judge–court records that were absent from the CourtListener person–position links, increasing the reference set from 779 to 908 records. We then added eight manually verified supplemental records for edge cases identified during inspection of frequently unresolved author names. These records covered one documented name change in the Fifth Circuit and seven visiting-judge court associations involving six judges sitting by designation whose FJC records list only their home courts. We verified the supplemental gender information against the judges' FJC records. For the visiting-judge records, we recorded the earliest observed opinion year as the start date and documented the observed years in the audit notes; formal designation end dates were unavailable. The final reference set contains 916 judge–court records with recorded gender information.

The source-based stages in Steps 3 and 4 used an expanded matching pool. In addition to these 916 appellate judge–court records, the pool included 9,965 CourtListener judge–court records from courts outside the thirteen selected appellate courts. These additional records were available only to the cross-court matching tiers and permitted source attributions to be matched to judges sitting by designation.

## Step 1: Direct Structured Author Link

Step 1 used CourtListener's structured author identifier when available. This identifier links an opinion directly to the corresponding CourtListener person record, from which we obtained the recorded gender. Because the procedure relies on an explicit database relationship instead of inferred name similarity, it is the most direct assignment method in the cascade.

Step 1 resolved 10,234 opinions.

## Step 2: Recorded Author-Name Matching

For opinions without a structured author identifier, Step 2 used CourtListener's recorded author-name field, which generally contains the surname or a short name form of the authoring judge. Step 2 was restricted to opinions marked non-*per curiam* and with a non-empty author-name field. We normalized capitalization, punctuation, and whitespace while retaining compound surnames. We then applied the following matching hierarchy:

1. Exact surname match within the opinion's circuit
2. Compound-surname suffix match within the circuit
3. Exact surname match across the other selected circuits
4. Compound-surname suffix match across the other selected circuits

Suffix matching accommodated shortened forms of compound surnames, such as *Orsdel* for *Van Orsdel* or *Eve* for *St. Eve*. Cross-circuit matching accommodated judges sitting by designation, where the opinion belongs to one circuit but the judge is listed under another court in the reference data.

We assigned gender only when all candidates at the best available matching level shared the same recorded gender. If the best matching group contained both female and male candidates, or if no candidate could be identified, we left the opinion unresolved.

Step 2 resolved 408,245 additional opinions and therefore contributed the largest number of assignments in the cascade.

## Source-Based Author Attribution

The source-based fallback stages considered only published, non-*per curiam* opinions that remained unresolved after Steps 1 and 2. We excluded *per curiam* opinions because they are issued collectively instead of being attributed to an individual author. The HTML-based extraction in Step 4 additionally required a filing year of 1960 or later.

The publication-status restriction applied only to the source-based gender-assignment fallbacks, while the 1960 cutoff applied only to the HTML-based extraction. Opinions marked *per curiam* were excluded from Steps 2–4 but could still receive a gender assignment through the structured author identifier in Step 1. None of these restrictions affected inclusion in the Federal Appeals Corpus.

Unlike the predominantly surname-based recorded author names used in Step 2, the attributions extracted in Steps 3 and 4 more often contain a complete name or one or more initials. Both steps therefore use their own, more granular matching hierarchies, described below.

### Step 3: Structured XML Attribution

In Step 3, we parsed the structured source XML and extracted names from its dedicated author elements. We retained only entries referring to an individual judge and excluded collective or procedural labels such as *per curiam*, *by the court*, and similar expressions that do not identify an individual author.

We normalized the extracted full name, surname, first initial, and, where present, middle initial separately. Candidate judges were evaluated according to the following priority hierarchy:

1. Exact full-name match within the opinion's circuit
2. Initials-plus-surname match within the circuit
3. Exact full-name match across the expanded judge pool
4. Initials-plus-surname match across the expanded judge pool
5. Surname match within the circuit, restricted to judges whose recorded service period included the opinion year
6. Surname match within the circuit without the service-period restriction

The initials-based tiers required agreement on the first initial and, when an extractable middle initial was present, on the middle initial. The service-period restriction used the recorded start and end dates of the judge's service record to determine whether the service period included the opinion year. This temporal check reduces erroneous matches between judges with the same surname who served during different periods. We retained a same-circuit surname match without the temporal restriction as a lower-priority fallback because service dates may be incomplete or may not fully represent service by designation.

For each opinion, we retained only candidates from the highest-priority matching tier that produced at least one candidate. We assigned gender when this tier contained a single judge or when all judges in the tier shared the same recorded gender. If the best tier contained both female and male candidates, or if no candidate was found, the opinion remained unresolved.

Step 3 resolved 11,514 additional opinions.

### Step 4: HTML Attribution Patterns

In Step 4, we extracted conventional author-attribution formulations from the citation-linked HTML representation. Because document structure varies across the underlying source collections, we first distinguished four layouts:

- Structured Harvard HTML
- Preformatted inline HTML
- XML-style inline HTML
- Generic HTML

For non-Harvard layouts, we produced both a whitespace-normalized text representation and a line-preserving representation. We applied layout-specific attribution patterns in a fixed priority order and retained the first valid extracted candidate. Table 1 summarizes the extraction patterns. The labels H1–H8 are used only to organize the presentation.

**Table 1.** Author-attribution patterns used in the HTML-based extraction.

| Pattern | Applicable layout | Attribution format and restrictions |
|---|---|---|
| H1 | Non-Harvard | *Opinion by [Chief/Senior] [Circuit] Judge NAME*. Treated as a strong attribution pattern. |
| H2 | Non-Harvard | *Opinion by NAME, [Chief/Senior] [Circuit/District] Judge*. Treated as a strong attribution pattern. |
| H3 | Non-Harvard | *Judge NAME delivered the opinion*. Used as a normalized-text fallback. |
| H4 | Generic and XML-inline | *NAME, [Chief/Senior] [Circuit/District] Judge*. Applied to line-preserving text. |
| H5 | Preformatted inline | *NAME, [Chief/Senior] Circuit Judge*. District-judge lines were excluded because they frequently identify the lower-court judge instead of the appellate author. |
| H6 | Generic and XML-inline | *NAME, Chief/Senior Judge*. Not used for preformatted opinions, where unqualified judicial-title lines are more easily confused with header material. |
| H7 | Structured Harvard | First attributed paragraph following an explicit *OPINION* heading and containing a judicial title. |
| H8 | Structured Harvard | First attributed paragraph containing a judicial title when no explicit *OPINION* heading is available. |

Before matching the extracted names, we removed candidates associated with panel lists, nearby *Before* headers, lists containing multiple judges, collective or procedural labels, party names, and institutional terms. For preformatted inline opinions, we limited the relevant line-anchored pattern to *Circuit Judge* attributions because lines naming a district judge often identify the judge whose decision was under review instead of the appellate author.

We separately normalised the extracted full name, surname, first initial, middle initial, compound-surname form, and suffix-stripped surname. Candidate judges were then evaluated according to the following priority hierarchy:

1. Exact full-name match within the opinion's circuit
2. Initials-plus-surname match within the circuit
3. Exact full-name match across the expanded judge pool
4. Initials-plus-surname match across the expanded judge pool
5. Surname match within the circuit, restricted to judges whose recorded service period included the opinion year
6. Surname match within the circuit without the service-period restriction
7. Surname match across the expanded judge pool, restricted to judges whose recorded service period included the opinion year
8. Surname match across the expanded judge pool without the service-period restriction
9. Compound-surname match within the circuit
10. Suffix-stripped surname match within the circuit and within the judge's recorded service period
11. Suffix-stripped surname match within the circuit without the service-period restriction

The exact-name tiers used the complete normalized attribution. Initials-based tiers required agreement on the surname and first initial and, when available, the middle initial. Surname-based tiers used an available first initial to narrow the candidate set. Service-period tiers prioritised judges whose recorded service included the opinion's filing year; unrestricted tiers remained as fallbacks for incomplete service records or service by designation. Additional tiers accounted for compound surnames and generational suffixes.

Only candidates from the first successful tier were considered. Gender was assigned when the tier identified one judge or when all candidates had the same recorded gender. Mixed-gender candidate groups and unmatched cases remained unresolved.

Step 4 resolved 125,304 additional opinions.

## Representative Extraction Examples

Table 2 presents representative extractions across the source formats. The examples illustrate variation in the available attribution formats, the subsequent matching to the judge reference set, and one case in which no unambiguous assignment was possible.

**Table 2.** Representative author-attribution extractions.

| Source | Extracted attribution | Matched judge | Gender |
|---|---|---|---|
| Structured XML | *KELLY, Circuit Judge* | Jane Kelly, Eighth Circuit | Female |
| Structured XML | *D.W. NELSON, Circuit Judge* | Dorothy Nelson, Ninth Circuit | Female |
| Generic HTML | *Opinion by Judge B. Fletcher* | Betty Fletcher, Ninth Circuit | Female |
| Preformatted HTML | *SILER, Circuit Judge* | Eugene Siler, Sixth Circuit | Male |
| Structured Harvard HTML | *DAVID R. THOMPSON, Circuit Judge* | David Thompson, Ninth Circuit | Male |
| XML-inline HTML | *SOLOMON, Senior District Judge* | Gus Solomon, District of Oregon | Male |
| Structured XML | *COMISKEY, District Judge* | No unambiguous match | Unresolved |

## Assignment Coverage

Table 3 summarises the coverage of the four-stage assignment cascade. Because each stage processed only opinions unresolved by the preceding stages, the step-specific counts are mutually exclusive. Overall, the procedure assigned author gender to 555,297 opinions (37.7% of the corpus), including 69,936 opinions attributed to female judges and 485,361 to male judges. The remaining 917,236 opinions were left unresolved and excluded from analyses requiring author gender.

A resolved gender does not imply that the author was identified. The cascade assigns a gender whenever all candidates in the best matching tier share the same recorded gender, which can hold for a tier containing several judges. An individual judge was identified for 524,777 of the 555,297 gender-resolved opinions (94.5%), covering 2,074 judges. The released table marks this subset with `person_unique`, and only it supports judge-level analyses.

These figures measure assignment coverage, not assignment accuracy. Manual validation of a stratified sample is ongoing, so no precision estimate is reported here.

**Table 3.** Opinions resolved at each step of the author-gender assignment cascade. Step-specific counts are mutually exclusive.

| Step | Assignment source | Additional resolved | Cumulative resolved | Cumulative share |
|---|---|---:|---:|---:|
| 1 | Structured author link | 10,234 | 10,234 | 0.7% |
| 2 | Recorded author name | 408,245 | 418,479 | 28.4% |
| 3 | Structured XML attribution | 11,514 | 429,993 | 29.2% |
| 4 | HTML opinion-text attribution | 125,304 | 555,297 | 37.7% |
| | **Gender resolved** | **555,297** | **555,297** | **37.7%** |
| | Unresolved | 917,236 | — | 62.3% |

## Implementation

| Stage | Script |
|---|---|
| Step 1, structured author link | [`01_create_step1_author_id.sql`](../deposit_pipeline/03_gender_assignment/01_create_step1_author_id.sql) |
| Step 2, recorded author name | [`03_create_step2_author_str.sql`](../deposit_pipeline/03_gender_assignment/03_create_step2_author_str.sql) |
| Steps 3 and 4, source-based attribution | [`08_create_steps3_4_text_extraction.sql`](../deposit_pipeline/03_gender_assignment/08_create_steps3_4_text_extraction.sql) |
| Final gender table | [`09_create_final_gender_table.sql`](../deposit_pipeline/03_gender_assignment/09_create_final_gender_table.sql) |
| Judge reference set | [`01_create_fjc_judge_tables.sql`](../deposit_pipeline/02_judge_reference/01_create_fjc_judge_tables.sql), [`03_create_fjc_court_name_map.sql`](../deposit_pipeline/02_judge_reference/03_create_fjc_court_name_map.sql), [`04_create_supplemental_judges.sql`](../deposit_pipeline/02_judge_reference/04_create_supplemental_judges.sql) |
| `person_unique` flag | [`01_unique_person_attribution.sql`](../deposit_pipeline/05_deposit/01_unique_person_attribution.sql) |

## References

- Federal Judicial Center. *Biographical Directory of Article III Federal Judges*. <https://www.fjc.gov/history/judges>
