from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

BASE = Path("/data/workspace/kmayer/courtlistener")
CSV_DIR = BASE / "cleaned_csv"
FIG_DIR = BASE / "figures"
FIG_DIR.mkdir(exist_ok=True)

plt.rcParams.update({
    "font.size": 12,
    "axes.labelsize": 12,
    "xtick.labelsize": 11,
    "ytick.labelsize": 11,
})

def read_csv(name: str) -> pd.DataFrame:
    path = CSV_DIR / name
    if not path.exists():
        raise FileNotFoundError(f"CSV not found: {path}")
    return pd.read_csv(path)

def main() -> None:
    df = read_csv("active_judges_female_share_by_party.csv")

    df["female_share_pct"] = pd.to_numeric(df["female_share_pct"], errors="coerce")
    df["female_active_judges"] = pd.to_numeric(df["female_active_judges"], errors="coerce")
    df["total_active_judges"] = pd.to_numeric(df["total_active_judges"], errors="coerce")

    order = ["Democratic", "Republican"]
    df["political_party_group"] = pd.Categorical(
        df["political_party_group"], categories=order, ordered=True
    )
    df = df.sort_values("political_party_group", ascending=True)

    color_map = {
        "Democratic": "tab:blue",
        "Republican": "tab:red",
    }

    fig, ax = plt.subplots(figsize=(9, 5.5))
    bars = ax.barh(
        df["political_party_group"],
        df["female_share_pct"],
        color=[color_map[p] for p in df["political_party_group"]],
    )

    ax.set_xlabel("Female share among active judges (%)")
    ax.set_ylabel("Political affiliation")
    ax.set_xlim(0, 45)

    ax.grid(axis="x", linestyle=":", linewidth=0.8, alpha=0.5)
    ax.set_axisbelow(True)
    ax.xaxis.set_major_formatter(mticker.StrMethodFormatter("{x:.0f}"))

    for bar, pct, female_n, total_n in zip(
        bars,
        df["female_share_pct"],
        df["female_active_judges"],
        df["total_active_judges"],
    ):
        ax.text(
            bar.get_width() + 0.6,
            bar.get_y() + bar.get_height() / 2,
            f"{pct:.1f}%\n(n={int(female_n):,} of {int(total_n):,})",
            ha="left",
            va="center",
            fontsize=10,
        )

    plt.tight_layout()
    plt.savefig(
        FIG_DIR / "active_judges_female_share_by_party.png",
        dpi=300,
        bbox_inches="tight",
    )
    plt.close()

    print(f"Saved plot to: {FIG_DIR / 'active_judges_female_share_by_party.png'}")

if __name__ == "__main__":
    main()