from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt


BASE = Path("/data/workspace/kmayer/courtlistener")
CSV_DIR = BASE / "cleaned_csv"
FIG_DIR = BASE / "figures"
FIG_DIR.mkdir(exist_ok=True)

BLUE = "#0072B2"
VERMILLION = "#D55E00"
GRID_COLOR = "#d7dce2"
TEXT_COLOR = "#20252b"

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


def main() -> None:
    df = pd.read_csv(CSV_DIR / "appointments_by_party_over_time.csv")
    df["year"] = pd.to_numeric(df["year"], errors="coerce")
    df["n_appointments"] = pd.to_numeric(df["n_appointments"], errors="coerce")
    df = df.dropna(subset=["year", "n_appointments"])
    df = df[(df["year"] >= 1920) & (df["year"] <= 2021)].copy()

    pivot = df.pivot(index="year", columns="political_party_clean", values="n_appointments").fillna(0)
    pivot["total"] = pivot.sum(axis=1)
    pivot["dem_share"] = pivot["Democratic"] / pivot["total"] * 100
    pivot["rep_share"] = pivot["Republican"] / pivot["total"] * 100

    # Smooth with 5-year rolling average
    pivot["dem_smooth"] = pivot["dem_share"].rolling(5, center=True, min_periods=3).mean()
    pivot["rep_smooth"] = pivot["rep_share"].rolling(5, center=True, min_periods=3).mean()

    # Coverage drops sharply from 2022 onward
    CUTOFF = 2021

    fig, ax = plt.subplots(figsize=(7.2, 3.8))

    # Full reliable period: solid lines + fill
    rel = pivot[pivot.index <= CUTOFF]
    ax.plot(
        rel.index,
        rel["dem_smooth"],
        color=BLUE,
        linewidth=2,
        linestyle="-",
        label="Democratic",
    )
    ax.plot(
        rel.index,
        rel["rep_smooth"],
        color=VERMILLION,
        linewidth=2,
        linestyle="--",
        label="Republican",
    )
    ax.fill_between(rel.index, rel["dem_smooth"], rel["rep_smooth"],
                    where=rel["dem_smooth"] >= rel["rep_smooth"],
                    interpolate=True, alpha=0.12, color=BLUE)
    ax.fill_between(rel.index, rel["dem_smooth"], rel["rep_smooth"],
                    where=rel["dem_smooth"] < rel["rep_smooth"],
                    interpolate=True, alpha=0.12, color=VERMILLION)

    ax.set_xlabel("Year")
    ax.set_ylabel("Share of persons (%)")
    ax.set_xlim(pivot.index.min(), CUTOFF)
    ax.set_ylim(0, 100)
    ax.grid(axis="y", color=GRID_COLOR, linestyle=":", linewidth=0.7)
    ax.set_axisbelow(True)
    ax.legend(
        frameon=False,
        loc="upper right",
    )

    plt.tight_layout()
    plt.savefig(FIG_DIR / "appointments_by_party_over_time.png", dpi=300, bbox_inches="tight")
    plt.close()
    print(f"Saved to: {FIG_DIR / 'appointments_by_party_over_time.png'}")


if __name__ == "__main__":
    main()
