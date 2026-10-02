"""Score the manual validation sample of author attributions.

Reads the annotated CSV produced by sql/derived/03_validation_sample.sql
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
    python python/12_score_validation_sample.py \
        [export/deposit/author_attribution_validation_sample_TO_ANNOTATE.csv]

There is deliberately only ONE sample file: the one that gets annotated is
the one that gets scored.

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
DEFAULT_IN = BASE / "export/deposit/author_attribution_validation_sample_TO_ANNOTATE.csv"
CSV_DIR = BASE / "cleaned_csv"

STEP_LABELS = {
    1: "structured author_id",
    2: "recorded author name",
    3: "XML author element",
    4: "HTML attribution formula",
}

VALID_VERDICTS = {"correct", "incorrect", "unclear"}


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

    required = {"opinion_id", "attribution_step", "stratum_size", "verdict"}
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

    CSV_DIR.mkdir(exist_ok=True)
    out = CSV_DIR / "author_attribution_validation_precision.csv"
    res.to_csv(out, index=False)
    print(f"\nWritten: {out}")


if __name__ == "__main__":
    main()
