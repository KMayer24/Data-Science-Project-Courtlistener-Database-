from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

BASE = Path("/data/workspace/kmayer/courtlistener")
CSV_DIR = BASE / "cleaned_csv"
FIG_DIR = BASE / "figures"
FIG_DIR.mkdir(exist_ok=True)

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
})


def main() -> None:
    df = pd.read_csv(CSV_DIR / "clusters_by_year_tier.csv")
    required_columns = {"court_category", "year", "n"}
    if not required_columns.issubset(df.columns):
        raise ValueError(
            "Unexpected columns in clusters_by_year_tier.csv: "
            f"{list(df.columns)}"
        )

    df["year"] = pd.to_numeric(df["year"], errors="raise").astype(int)
    df["n"] = pd.to_numeric(df["n"], errors="raise")
    df = df[(df["year"] >= 1950) & (df["year"] <= 2020)]

    pivot = df.pivot(index="year", columns="court_category", values="n").fillna(0)
    pivot = pivot.rolling(3, center=True, min_periods=2).mean()

    category_order = [
        "U.S. Supreme Court/Federal Appeals",
        "Federal District/Bankruptcy/Special",
        "State Supreme/Appellate",
        "State Trial/Other",
    ]
    category_order = [category for category in category_order if category in pivot.columns]
    # Two high-contrast ColorBrewer families distinguish the federal and state
    # systems while preserving the visual style of the original figure.
    category_color_map = {
        "U.S. Supreme Court/Federal Appeals": "#2B5A8A",
        "Federal District/Bankruptcy/Special": "#74A9CF",
        "State Supreme/Appellate": "#E6550D",
        "State Trial/Other": "#FDAE6B",
    }
    category_colors = [category_color_map[category] for category in category_order]

    fig, ax = plt.subplots(figsize=(7.2, 3.8))
    ax.stackplot(
        pivot.index,
        [pivot[category] for category in category_order],
        labels=category_order,
        colors=category_colors,
        alpha=0.85,
        edgecolor="white",
        linewidth=0.25,
    )
    ax.set_xlabel("Filing year")
    ax.set_ylabel("Recorded opinion clusters")
    ax.set_xlim(1950, 2020)
    ax.yaxis.set_major_formatter(
        mticker.FuncFormatter(lambda x, _: f"{int(x):,}")
    )
    ax.grid(axis="y", color="#d7dce2", linestyle=":", linewidth=0.7)
    ax.set_axisbelow(True)
    handles, labels = ax.get_legend_handles_labels()
    ax.legend(
        handles[::-1],
        labels[::-1],
        title="Court category",
        frameon=False,
        loc="upper left",
        alignment="left",
    )

    plt.tight_layout()
    plt.savefig(
        FIG_DIR / "clusters_by_year_tier.png", dpi=300, bbox_inches="tight"
    )
    plt.close()
    print(f"Saved to: {FIG_DIR / 'clusters_by_year_tier.png'}")


if __name__ == "__main__":
    main()
