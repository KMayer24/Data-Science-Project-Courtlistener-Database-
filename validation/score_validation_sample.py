"""Score the manual validation sample of author attributions.

Reads the manually annotated CSV drawn by ``build_validation_sample.ipynb``
and reports precision per attribution step, with Wilson 95 % confidence
intervals, plus a corpus-weighted precision over all uniquely attributed
opinions.

The sample is stratified by attribution step and allocated by risk, not
equally and not proportionally: step 1 carries a small control sample
because it uses CourtListener's structured author_id link and does no
name matching, while steps 2 to 4 carry the matching and get the bulk of
the budget. The unweighted mean across steps is therefore NOT the corpus
precision; the corpus-weighted figure uses the stratum sizes carried in
the file.

Usage:
    python validation/score_validation_sample.py [annotated-sample.csv]

With no argument, the script reads the published annotated sample in this
directory.

The 'verdict' column must be filled with one of:
    correct | incorrect | unclear
Rows with an empty verdict are reported as not yet annotated and are
excluded from the precision estimates.
"""

import sys
from math import sqrt
from pathlib import Path

import pandas as pd

BASE = Path(__file__).resolve().parents[1]
VALIDATION_DIR = BASE / "validation"
DEFAULT_IN = VALIDATION_DIR / "author_attribution_validation_sample_annotated.csv"
DEFAULT_OUT = VALIDATION_DIR / "author_attribution_validation_precision.csv"

STEP_LABELS = {
    1: "structured author_id",
    2: "recorded author name",
    3: "XML author element",
    4: "HTML attribution formula",
}

VALID_VERDICTS = {"correct", "incorrect", "unclear"}
VALID_ERROR_SOURCES = {"courtlistener", "extraction", "matching"}


def wilson(successes: int, total: int, z: float = 1.96):
    """Wilson score interval; more honest than the normal approximation
    at the small stratum sizes used here."""
    if total == 0:
        return (float("nan"), float("nan"))
    p = successes / total
    denom = 1 + z**2 / total
    centre = (p + z**2 / (2 * total)) / denom
    margin = z * sqrt(p * (1 - p) / total + z**2 / (4 * total**2)) / denom
    return (max(0.0, centre - margin), min(1.0, centre + margin))


def main() -> None:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_IN
    if not path.exists():
        raise SystemExit(f"Annotated sample not found: {path}")

    df = pd.read_csv(path)

    required = {
        "opinion_id",
        "attribution_step",
        "stratum_size",
        "verdict",
        "correct_judge_if_incorrect",
        "error_source",
    }
    missing = required - set(df.columns)
    if missing:
        raise SystemExit(f"Missing columns in {path}: {sorted(missing)}")

    df["verdict"] = df["verdict"].astype("string").str.strip().str.lower()

    bad = set(df["verdict"].dropna().unique()) - VALID_VERDICTS
    if bad:
        raise SystemExit(
            f"Unexpected values in 'verdict': {sorted(bad)}. "
            f"Allowed: {sorted(VALID_VERDICTS)}"
        )

    if df["opinion_id"].duplicated().any():
        duplicate_ids = df.loc[df["opinion_id"].duplicated(), "opinion_id"].tolist()
        raise SystemExit(f"Duplicate opinion_id values: {duplicate_ids}")

    incorrect = df["verdict"] == "incorrect"
    missing_judge = incorrect & df["correct_judge_if_incorrect"].isna()
    missing_source = incorrect & df["error_source"].isna()
    if missing_judge.any() or missing_source.any():
        raise SystemExit(
            "Every incorrect row must provide correct_judge_if_incorrect "
            "and error_source"
        )

    sources = df.loc[incorrect, "error_source"].astype("string").str.strip().str.lower()
    bad_sources = set(sources.dropna().unique()) - VALID_ERROR_SOURCES
    if bad_sources:
        raise SystemExit(
            f"Unexpected error_source values: {sorted(bad_sources)}. "
            f"Allowed: {sorted(VALID_ERROR_SOURCES)}"
        )

    n_total = len(df)
    n_annotated = int(df["verdict"].notna().sum())
    print(f"Sample rows        : {n_total}")
    print(f"Annotated          : {n_annotated}")
    if n_annotated == 0:
        print("\nNothing annotated yet -- fill the 'verdict' column first.")
        return
    if n_annotated < n_total:
        print(f"Not yet annotated  : {n_total - n_annotated} (excluded below)")
    print()

    rows = []
    for step, grp in df.groupby("attribution_step", sort=True):
        judged = grp[grp["verdict"].isin(["correct", "incorrect"])]
        unclear = int((grp["verdict"] == "unclear").sum())
        n = len(judged)
        correct = int((judged["verdict"] == "correct").sum())
        lo, hi = wilson(correct, n)
        rows.append(
            {
                "step": int(step),
                "step_label": STEP_LABELS.get(int(step), ""),
                "stratum_size": int(grp["stratum_size"].iloc[0]),
                "n_annotated": int(grp["verdict"].notna().sum()),
                "n_judged": n,
                "n_unclear": unclear,
                "n_correct": correct,
                "precision": correct / n if n else float("nan"),
                "ci_low": lo,
                "ci_high": hi,
            }
        )

    res = pd.DataFrame(rows)

    print(
        f"{'step':<5}{'label':<28}{'judged':>7}{'correct':>9}"
        f"{'precision':>11}{'95% CI':>20}{'unclear':>9}"
    )
    for _, r in res.iterrows():
        ci = f"[{r.ci_low:.3f}, {r.ci_high:.3f}]"
        print(
            f"{r.step:<5}{r.step_label:<28}{r.n_judged:>7}{r.n_correct:>9}"
            f"{r.precision:>11.3f}{ci:>20}{r.n_unclear:>9}"
        )

    judged_total = int(res["n_judged"].sum())
    correct_total = int(res["n_correct"].sum())

    # Corpus-weighted precision: weight each stratum by its share of all
    # uniquely attributed opinions, not by its share of the sample.
    usable = res[res["n_judged"] > 0]
    weights = usable["stratum_size"] / usable["stratum_size"].sum()
    weighted = float((usable["precision"] * weights).sum())

    print()
    print(f"Pooled over sample (unweighted): {correct_total}/{judged_total} = "
          f"{correct_total / judged_total:.3f}")
    print(f"Corpus-weighted precision      : {weighted:.3f}")
    if len(usable) < len(res):
        print("  (weighted figure covers only the steps with judged rows)")

    DEFAULT_OUT.parent.mkdir(exist_ok=True)
    res.to_csv(DEFAULT_OUT, index=False)
    print(f"\nWritten: {DEFAULT_OUT}")


if __name__ == "__main__":
    main()
