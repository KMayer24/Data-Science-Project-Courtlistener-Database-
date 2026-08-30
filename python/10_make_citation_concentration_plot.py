from pathlib import Path

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

BASE = Path("/data/workspace/kmayer/courtlistener")
FIG_DIR = BASE / "figures"
FIG_DIR.mkdir(exist_ok=True)

plt.rcParams.update({
    "font.size": 12,
    "axes.labelsize": 12,
    "xtick.labelsize": 11,
    "ytick.labelsize": 11,
})

# Pre-computed from citation_buckets.csv (filed 1950-2010)
BUCKETS = ["0\n(never cited)", "1–5", "6–20", "21–100", "100+"]
COUNTS  = [2_260_857, 1_170_330, 920_219, 452_601, 70_829]
COLORS  = ["#c6dbef", "#9ecae1", "#6baed6", "#2171b5", "#08306b"]


def main() -> None:
    total  = sum(COUNTS)
    shares = [c / total * 100 for c in COUNTS]

    fig, ax = plt.subplots(figsize=(9, 5))
    bars = ax.bar(BUCKETS, shares, color=COLORS, width=0.6)

    for bar, share, count in zip(bars, shares, COUNTS):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + 0.3,
            f"{share:.1f}%\n({count / 1e6:.2f}M)",
            ha="center", va="bottom", fontsize=9.5,
        )

    ax.set_xlabel("Incoming citations per opinion cluster")
    ax.set_ylabel("Share of all clusters (%)")
    ax.set_ylim(0, 55)
    ax.yaxis.set_major_formatter(
        mticker.FuncFormatter(lambda x, _: f"{x:.0f}%")
    )
    ax.grid(axis="y", linestyle=":", linewidth=0.8, alpha=0.5)
    ax.set_axisbelow(True)
    ax.text(
        0.99, 0.97,
        f"N\u2009=\u2009{total / 1e6:.1f}M opinion clusters\n(filed 1950\u20132010)",
        transform=ax.transAxes, ha="right", va="top", fontsize=9, color="gray",
    )

    plt.tight_layout()
    plt.savefig(
        FIG_DIR / "citation_concentration.png", dpi=300, bbox_inches="tight"
    )
    plt.close()
    print(f"Saved to: {FIG_DIR / 'citation_concentration.png'}")


if __name__ == "__main__":
    main()
