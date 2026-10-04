# Manual validation of author attribution

This directory contains the complete audit trail for the manual validation of
the federal appellate opinion-author attribution. It separates three tasks:
the reproducible draw, the human decisions, and the statistical summary.

The manual-validation files were added after publication of the fixed Zenodo
dataset version and are therefore distributed through this GitHub repository,
not as files within that already published Zenodo record. The notebook draws
from a restored copy of the deposited database, so the audited population
remains the population identified by the dataset DOI.

## Files

| File | Purpose |
|---|---|
| `build_validation_sample.ipynb` | Draws the deterministic stratified sample from a restored release and attaches the evidence needed for annotation |
| `author_attribution_validation_sample_annotated.csv` | The 200 sampled opinions and the completed manual annotations |
| `score_validation_sample.py` | Validates the annotation fields and calculates precision and Wilson 95% confidence intervals by attribution step |
| `author_attribution_validation_precision.csv` | Machine-readable output of the scoring script |

The generated, unannotated worksheet is intentionally not versioned. Running
the notebook recreates it as
`validation/author_attribution_validation_sample_to_annotate.csv`.

## Sampling design

The sampling frame consists of the 524,777 opinions for which the released
attribution table identifies one person. The sample is stratified by the four
sequential attribution steps:

| Step | Attribution source | Population | Sample |
|---:|---|---:|---:|
| 1 | CourtListener structured `author_id` | 10,234 | 20 |
| 2 | Recorded author name | 380,935 | 60 |
| 3 | XML author element | 11,499 | 60 |
| 4 | HTML attribution formula | 122,109 | 60 |

Within each step, opinions are ordered by
`md5(opinion_id || 'epjds-validation-2026')`. This keyed-hash ordering is
independent of court, year, gender, tier, and match outcome, and reproduces the
same sample without relying on database row order or a library-specific random
number generator.

## Reproduce the draw

The notebook reads a restored copy of the published database. The restored
release must contain `deposit.opinion_author_attribution`,
`deposit.opinion_author_attribution_diagnostics`, `deposit.appellate_opinion`,
`public.people_db_person`, and the opinion text table `public.search_opinion`.
All notebook queries are read-only.

Configure the connection before starting Jupyter:

```bash
export RESTORE_DB=courtlistener_release_restore
export RESTORE_HOST=/path/to/postgresql/socket  # omit for the default socket
export RESTORE_PORT=5432
jupyter lab validation/build_validation_sample.ipynb
```

`VALIDATION_SAMPLE_OUT` can be set to use a different output path. If it is
unset, the notebook writes the ignored unannotated worksheet in this
directory. Database restoration is documented in the repository root README
and in `restore_deposit.sh`.

## Annotation rule

For each row, the annotator compared `matched_judge` with the opinion-author
line in `text_excerpt`. Panel membership alone was not treated as authorship.
The allowed verdicts are:

| Verdict | Meaning |
|---|---|
| `correct` | The opinion identifies `matched_judge` as its author |
| `incorrect` | The opinion identifies a different author |
| `unclear` | The excerpt does not establish the author |

An `incorrect` row also records `correct_judge_if_incorrect` and one of three
error sources: `courtlistener`, `extraction`, or `matching`. The notebook and
the scoring script do not assign verdicts; the decisions in the annotated CSV
were entered manually.

## Score the annotations

From the repository root, run:

```bash
python3 validation/score_validation_sample.py
```

An alternative annotated CSV may be supplied as the first positional
argument. The script rejects unknown verdicts, duplicate opinion identifiers,
and incomplete error records before writing
`author_attribution_validation_precision.csv`.

## Results

All 200 sampled opinions were annotated; none was `unclear`.

| Step | Judged | Correct | Precision | Wilson 95% CI |
|---:|---:|---:|---:|---:|
| 1 | 20 | 16 | 0.800 | [0.584, 0.919] |
| 2 | 60 | 60 | 1.000 | [0.940, 1.000] |
| 3 | 60 | 60 | 1.000 | [0.940, 1.000] |
| 4 | 60 | 60 | 1.000 | [0.940, 1.000] |

The pooled, unweighted precision is 196/200, or 0.980. Weighting the
step-specific estimates by their population sizes gives 0.996. All four
observed errors were incorrect structured `author_id` links in the upstream
CourtListener data (step 1); none was produced by the name-extraction or
matching steps in this sample.

The CourtListener-derived excerpts retain their source-data status. The manual
annotations and precision summary are released under the repository's
[CC BY 4.0 data licence](../LICENSE-DATA.md); the notebook and scoring script
are covered by the [MIT code licence](../LICENSE-CODE.md).
