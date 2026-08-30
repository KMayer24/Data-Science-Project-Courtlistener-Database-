from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.lines import Line2D

BASE = Path("/data/workspace/kmayer/courtlistener")
CSV_DIR = BASE / "cleaned_csv"
FIG_DIR = BASE / "figures"
FIG_DIR.mkdir(exist_ok=True)

BLUE = "#0072B2"
PARTIAL_COLOR = "#56B4E9"
GRID_COLOR = "#d7dce2"
TEXT_COLOR = "#20252b"
MISSING_LINE_COLOR = "#555555"

plt.rcParams.update({
    "font.family": "serif",
    "font.serif": ["Latin Modern Roman", "DejaVu Serif"],
    "font.size": 10,
    "axes.labelsize": 10,
    "xtick.labelsize": 9,
    "ytick.labelsize": 9,
    "legend.fontsize": 9,
    "legend.title_fontsize": 9.5,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.edgecolor": "#707780",
    "text.color": TEXT_COLOR,
    "axes.labelcolor": TEXT_COLOR,
    "xtick.color": TEXT_COLOR,
    "ytick.color": TEXT_COLOR,
})

PARTIAL = 2020  # 2020s decade is incomplete


def main() -> None:
    df = pd.read_csv(CSV_DIR / "appointments_by_gender_decade.csv", header=None, names=["gender", "decade", "n"])
    pivot = df.pivot(index="decade", columns="gender", values="n").fillna(0)
    pivot["known"] = pivot["Female"] + pivot["Male"]
    pivot["female_share"] = pivot["Female"] / pivot["known"] * 100
    pivot["missing_pct"] = (
        pivot["Missing"] / (pivot["known"] + pivot["Missing"]) * 100
    )

    colors = [BLUE if d < PARTIAL else PARTIAL_COLOR for d in pivot.index]

    fig, ax = plt.subplots(figsize=(7.2, 3.8))
    bars = ax.bar(pivot.index, pivot["female_share"],
                  width=7, color=colors, alpha=0.9)

    ax.plot(
        pivot.index,
        pivot["missing_pct"],
        color=MISSING_LINE_COLOR,
        linewidth=1.1,
        linestyle="--",
        marker="D",
        markersize=3.5,
        markerfacecolor="white",
        markeredgewidth=0.8,
        zorder=3,
    )

    for bar, val in zip(bars, pivot["female_share"]):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + 0.5,
            f"{val:.1f}%",
            ha="center", va="bottom", fontsize=8.5,
            color=TEXT_COLOR,
        )

    ax.set_xlabel("Decade of recorded position start")
    ax.set_ylabel("Share of persons (%)")
    ax.set_xlim(1915, 2028)
    ax.set_ylim(0, 54)
    ax.set_xticks(pivot.index)
    ax.set_xticklabels([f"{d}s" for d in pivot.index])
    ax.grid(axis="y", color=GRID_COLOR, linestyle=":", linewidth=0.7)
    ax.set_axisbelow(True)

    full_patch = mpatches.Patch(
        color=BLUE,
        alpha=0.9,
        label="Female share (known gender)",
    )
    part_patch = mpatches.Patch(
        facecolor=PARTIAL_COLOR,
        alpha=0.9,
        label="Female share (partial 2020s)",
    )
    missing_line = Line2D(
        [0], [0],
        color=MISSING_LINE_COLOR,
        linewidth=1.1,
        linestyle="--",
        marker="D",
        markersize=3.5,
        markerfacecolor="white",
        label="Missing-gender share",
    )
    ax.legend(
        handles=[full_patch, part_patch, missing_line],
        frameon=False,
        loc="upper left",
    )

    plt.tight_layout()
    plt.savefig(
        FIG_DIR / "female_share_appointments_by_decade.png",
        dpi=300, bbox_inches="tight",
    )
    plt.close()
    print(f"Saved to: {FIG_DIR / 'female_share_appointments_by_decade.png'}")


if __name__ == "__main__":
    main()
