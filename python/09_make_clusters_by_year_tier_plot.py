"""Figure 2: recorded opinion clusters by court category, 1950-2025.

The publication figure answers one question: how much is recorded, and by
which courts? Absolute cluster counts are stacked by court category. Detailed
provenance diagnostics remain available in the exported data and console
output, but are deliberately kept out of the main-paper figure.

Two earlier versions got the provenance wrong. The first drew RECAP as a
fifth *court* category, which classified records by provenance instead of by
court and emptied the bands beside it: in 2024, 10,217 of 17,287 federal
appellate clusters left the federal appellate band, which then read as
~7,000. The second kept the four court categories but read provenance from
`search_docket.source` bit 0. That bit marks a docket touched by RECAP,
which is not the same as an opinion obtained from RECAP, and for federal
appellate opinions the two diverge completely: in 2025, 58 % of federal
appellate clusters sit on a RECAP-flagged docket, yet none has a RECAP
cluster source -- 109,232 of 112,241 come from court websites.

Provenance is read from `search_opinioncluster.source`, the field that records
where the opinion itself was obtained. Its codes are defined in
CourtListener's ClusterSources: C court website, U Harvard Caselaw Access
Project, G recap, and Z/L/R/M/A/D/Q/S for the remaining archives. Values are
merges, so a cluster can carry several sources and source shares must not be
treated as a mutually exclusive composition.

Further decisions:

  * The series end at 2025, the last complete year. The snapshot is dated
    2026-03-31, so 2026 covers barely one quarter; it is excluded rather
    than drawn, and the caption says so.
  * No smoothing. An earlier version applied a centred three-year rolling
    mean, which both softens the jumps that are the whole point of the
    figure and leaves the final points resting on an incomplete window.

Colour is computed, not chosen by eye. The figure keeps four court hues whose
worst pair holds an OKLab dE of 16.7 under simulated protan, deutan and
tritan vision, clearing the dE >= 8 threshold.

A log-scale line variant is written alongside the main figure as a
diagnostic (see MAKE_LOG_VARIANT). It is not the figure to publish.
"""

from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from matplotlib.patches import Patch

BASE = Path("/data/workspace/kmayer/courtlistener")
CSV_DIR = BASE / "cleaned_csv"
FIG_DIR = BASE / "figures"
FIG_DIR.mkdir(exist_ok=True)

YEAR_MIN, YEAR_MAX = 1950, 2025
PARTIAL_YEAR = 2026          # snapshot 2026-03-31
MAKE_LOG_VARIANT = True
LAST_COMPLETE_YEAR = PARTIAL_YEAR - 1   # 2025, the last complete year

plt.rcParams.update({
    "font.family": "serif",
    "font.serif": ["Latin Modern Roman", "DejaVu Serif"],
    # Sized for reproduction at 170 mm text width: axis labels and ticks
    # up, legend down, so the legend stops dominating the panel.
    "font.size": 10,
    "axes.labelsize": 11,
    "xtick.labelsize": 10,
    "ytick.labelsize": 10,
    "legend.fontsize": 8.5,
    "legend.title_fontsize": 9,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.edgecolor": "#707780",
})

PROVENANCE_ORDER = [
    ("n_court_website", "Court website"),
    ("n_harvard", "Harvard Caselaw Access Project"),
    ("n_recap", "RECAP (PACER archive)"),
    ("n_other_archives", "Other archives"),
]
# Bottom to top in the stack. Federal district sits at the bottom because
# it carries most of the PACER archive; keeping it there stops the late
# RECAP growth from pushing the other bands around.
CATEGORY_ORDER = [
    "Federal District/Bankruptcy/Special",
    "U.S. Supreme Court/Federal Appeals",
    "State Supreme/Appellate",
    "State Trial/Other",
]

CATEGORY_COLORS = {
    "Federal District/Bankruptcy/Special": "#74A9CF",
    "U.S. Supreme Court/Federal Appeals": "#2B5A8A",
    "State Supreme/Appellate": "#E6550D",
    "State Trial/Other": "#FDAE6B",
}


def load() -> pd.DataFrame:
    df = pd.read_csv(CSV_DIR / "clusters_by_year_tier.csv")
    required_columns = {"court_category", "year", "n"}
    if not required_columns.issubset(df.columns):
        raise ValueError(
            "Unexpected columns in clusters_by_year_tier.csv: "
            f"{list(df.columns)} -- re-run sql/15_clusters_by_year_tier_export.sql."
        )
    df["year"] = pd.to_numeric(df["year"], errors="raise").astype(int)
    df["n"] = pd.to_numeric(df["n"], errors="raise")
    df = df[(df["year"] >= YEAR_MIN) & (df["year"] <= YEAR_MAX)]
    unexpected = set(df["court_category"]) - set(CATEGORY_ORDER)
    if unexpected:
        raise ValueError(f"Unknown court categories in export: {sorted(unexpected)}")
    return df


def load_provenance() -> pd.DataFrame:
    path = CSV_DIR / "clusters_by_year_provenance.csv"
    if not path.exists():
        raise FileNotFoundError(
            f"{path} is missing -- re-run sql/15_clusters_by_year_tier_export.sql, "
            "which now writes a provenance table alongside the court-category one."
        )
    prov = pd.read_csv(path)
    needed = {"year", "n_total"} | {k for k, _ in PROVENANCE_ORDER}
    if not needed.issubset(prov.columns):
        raise ValueError(f"Unexpected columns in {path.name}: {list(prov.columns)}")
    prov = prov[(prov["year"] >= YEAR_MIN) & (prov["year"] <= LAST_COMPLETE_YEAR)]
    return prov.set_index("year").sort_index()


def pivot_for_plot(df: pd.DataFrame) -> pd.DataFrame:
    pivot = df.pivot(index="year", columns="court_category", values="n").fillna(0)
    pivot = pivot.reindex(columns=CATEGORY_ORDER).fillna(0)
    return pivot.loc[pivot.index <= LAST_COMPLETE_YEAR]


def make_figure(pivot: pd.DataFrame) -> None:
    fig, ax = plt.subplots(figsize=(6.7, 3.45), layout="constrained")
    ax.stackplot(
        pivot.index,
        [pivot[c] for c in CATEGORY_ORDER],
        colors=[CATEGORY_COLORS[c] for c in CATEGORY_ORDER],
        alpha=0.85,
        edgecolor="white",
        linewidth=0.5,      # 2px-equivalent surface gap between bands
    )
    ax.set_xlabel("Filing year")
    ax.set_ylabel("Recorded opinion clusters")
    ax.set_xlim(YEAR_MIN, YEAR_MAX)
    ax.set_ylim(bottom=0)
    # Decades only, so the spacing stays even. The series ends with the last
    # complete year; the caption states that, and an extra tick there would
    # read as a decade boundary.
    ax.set_xticks(list(range(YEAR_MIN, 2021, 10)))
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{int(x):,}"))
    ax.grid(axis="y", color="#d7dce2", linestyle=":", linewidth=0.7)
    ax.set_axisbelow(True)
    ax.legend(
        handles=[Patch(facecolor=CATEGORY_COLORS[c], edgecolor="white",
                       alpha=0.85, label=c) for c in reversed(CATEGORY_ORDER)],
        title="Court category", frameon=False, loc="upper left",
        alignment="left", fontsize=8, title_fontsize=8.5,
    )

    out = FIG_DIR / "clusters_by_year_tier.png"
    plt.savefig(out, dpi=300, bbox_inches="tight")
    plt.savefig(out.with_suffix(".pdf"), bbox_inches="tight")
    plt.close()
    print(f"Saved: {out}")
    print(f"Saved: {out.with_suffix('.pdf')}")


def make_log_lines(pivot: pd.DataFrame) -> None:
    """Diagnostic only -- see the module docstring."""
    fig, ax = plt.subplots(figsize=(7.2, 3.8))
    for c in CATEGORY_ORDER:
        ax.plot(pivot.index, pivot[c].replace(0, float("nan")),
                label=c, color=CATEGORY_COLORS[c], linewidth=1.6)
    ax.set_yscale("log")
    ax.set_xlabel("Filing year")
    ax.set_ylabel("Recorded opinion clusters (log scale)")
    ax.set_xlim(YEAR_MIN, YEAR_MAX)
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{int(x):,}"))
    ax.grid(axis="y", color="#d7dce2", linestyle=":", linewidth=0.7)
    ax.set_axisbelow(True)
    handles, labels = ax.get_legend_handles_labels()
    ax.legend(handles[::-1], labels[::-1], title="Court category",
              frameon=False, loc="lower right", alignment="left", fontsize=7.5)
    plt.tight_layout()
    out = FIG_DIR / "clusters_by_year_tier_log_lines.png"
    plt.savefig(out, dpi=300, bbox_inches="tight")
    plt.close()
    print(f"Saved (diagnostic): {out}")


def main() -> None:
    pivot = pivot_for_plot(load())
    prov = load_provenance()
    make_figure(pivot)
    if MAKE_LOG_VARIANT:
        make_log_lines(pivot)

    fedapp = "U.S. Supreme Court/Federal Appeals"
    print("\nProvenance shares (clusters whose source includes X):")
    for y in (1990, 2010, 2015, 2018, 2020, 2025):
        if y in prov.index:
            parts = ", ".join(
                f"{label.split(' (')[0]} {prov.loc[y, key] / prov.loc[y, 'n_total']:.1%}"
                for key, label in PROVENANCE_ORDER
            )
            print(f"  {y}: {parts}")

    print(f"\n{fedapp}, court-based count:")
    for y in (2010, 2018, 2023, 2024, 2025):
        if y in pivot.index:
            print(f"  {y}: {int(pivot.loc[y, fedapp]):>7,}")


if __name__ == "__main__":
    main()
