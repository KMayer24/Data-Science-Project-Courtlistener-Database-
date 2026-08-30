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
    "legend.fontsize": 11,
})


def read_csv(name: str) -> pd.DataFrame:
    path = CSV_DIR / name
    if not path.exists():
        raise FileNotFoundError(f"CSV not found: {path}")
    return pd.read_csv(path)


def format_plain_numbers(ax) -> None:
    ax.ticklabel_format(style="plain", axis="x")
    ax.xaxis.set_major_formatter(mticker.StrMethodFormatter("{x:,.0f}"))


def apply_common_style(ax) -> None:
    ax.grid(axis="x", linestyle=":", linewidth=0.8, alpha=0.5)
    ax.set_axisbelow(True)


def main() -> None:
    df = read_csv("active_judges_by_gender_party.csv")
    df["n_active_judges"] = pd.to_numeric(df["n_active_judges"], errors="coerce")

    df = df[df["political_party_group"].isin(["Democratic", "Republican"])].copy()

    party_order = ["Democratic", "Republican"]
    gender_order = ["Male", "Female", "Missing"]

    df["party_total"] = df.groupby("political_party_group")["n_active_judges"].transform("sum")
    df["pct_within_party"] = 100 * df["n_active_judges"] / df["party_total"]

    df["political_party_group"] = pd.Categorical(
        df["political_party_group"], categories=party_order, ordered=True
    )
    df["gender_clean"] = pd.Categorical(
        df["gender_clean"], categories=gender_order, ordered=True
    )

    fig, ax = plt.subplots(figsize=(10, 6.5))

    bar_height = 0.22
    y_base = {
        "Democratic": 1.0,
        "Republican": 0.0,
    }
    y_offsets = {
        "Male": 0.24,
        "Female": 0.00,
        "Missing": -0.24,
    }

    color_map = {
        "Male": "tab:blue",
        "Female": "tab:orange",
        "Missing": "tab:gray",
    }

    max_val = df["n_active_judges"].max()
    ax.set_xlim(0, max_val * 1.28)

    for _, row in df.iterrows():
        party = row["political_party_group"]
        gender = row["gender_clean"]
        value = row["n_active_judges"]
        pct = row["pct_within_party"]

        y = y_base[str(party)] + y_offsets[str(gender)]

        ax.barh(
            y=y,
            width=value,
            height=bar_height,
            color=color_map[str(gender)],
            label=str(gender),
        )

        ax.text(
            value + max_val * 0.015,
            y,
            f"{int(value):,} ({pct:.1f}%)",
            va="center",
            ha="left",
            fontsize=10,
        )

    ax.set_yticks([y_base["Democratic"], y_base["Republican"]])
    ax.set_yticklabels(["Democratic", "Republican"])

    ax.set_xlabel("Number of active judges")
    ax.set_ylabel("Political affiliation")

    apply_common_style(ax)
    format_plain_numbers(ax)

    # Legende ohne Duplikate
    handles = [
        plt.Rectangle((0, 0), 1, 1, color=color_map[g]) for g in gender_order
    ]
    ax.legend(handles, gender_order, title="Gender", frameon=False, loc="lower right")

    plt.tight_layout()
    plt.savefig(
        FIG_DIR / "active_judges_by_gender_party.png",
        dpi=300,
        bbox_inches="tight"
    )
    plt.close()

    print(f"Saved plot to: {FIG_DIR / 'active_judges_by_gender_party.png'}")


if __name__ == "__main__":
    main()