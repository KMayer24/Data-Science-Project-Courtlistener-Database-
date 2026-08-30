from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from matplotlib.patches import Patch


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


def clean_category(series: pd.Series, missing_label: str = "Missing") -> pd.Series:
    return (
        series.astype("string")
        .fillna(missing_label)
        .replace({"<NA>": missing_label, "nan": missing_label, "None": missing_label})
        .str.strip()
        .replace("", missing_label)
    )


def shorten_labels(series: pd.Series, max_len: int = 40) -> pd.Series:
    return series.astype(str).str.strip().apply(
        lambda s: s if len(s) <= max_len else s[: max_len - 3] + "..."
    )


def recode_party(series: pd.Series) -> pd.Series:
    mapping = {
        "d": "Democratic",
        "r": "Republican",
        "missing": "Missing",
        "multiple": "Multiple",
    }

    cleaned = clean_category(series, missing_label="Missing").str.lower()

    def _map_value(x: str) -> str:
        if x in mapping:
            return mapping[x]
        if len(x) == 1:
            return x.upper()
        return x.title()

    return cleaned.map(_map_value)


def party_color_map() -> dict[str, str]:
    return {
        "Democratic": "tab:blue",
        "Republican": "tab:red",
        "Missing": "tab:gray",
        "Multiple": "tab:purple",
    }


def party_colors(series: pd.Series) -> list[str]:
    cmap = party_color_map()
    return [cmap.get(v, "tab:orange") for v in series]


def format_plain_numbers(ax) -> None:
    ax.ticklabel_format(style="plain", axis="x")
    ax.xaxis.set_major_formatter(mticker.StrMethodFormatter("{x:,.0f}"))


def apply_common_style(ax) -> None:
    ax.grid(axis="x", linestyle=":", linewidth=0.8, alpha=0.5)
    ax.set_axisbelow(True)


def add_horizontal_value_labels(ax, values: pd.Series) -> None:
    xmax = ax.get_xlim()[1]
    offset = xmax * 0.01

    for bar, value in zip(ax.patches, values):
        if pd.isna(value):
            continue

        ax.text(
            bar.get_width() + offset,
            bar.get_y() + bar.get_height() / 2,
            f"{int(value):,}",
            ha="left",
            va="center",
            fontsize=10,
        )


def save_top_panel_participation_plot(
    df: pd.DataFrame,
    label_col: str,
    value_col: str,
    party_col: str,
    outfile: str,
    top_n: int = 15,
) -> None:
    plot_df = df.copy()

    plot_df[label_col] = shorten_labels(plot_df[label_col], max_len=40)
    plot_df[party_col] = recode_party(plot_df[party_col])
    plot_df[value_col] = pd.to_numeric(plot_df[value_col], errors="coerce")
    plot_df = plot_df.dropna(subset=[value_col])

    plot_df = plot_df.sort_values(value_col, ascending=False).head(top_n).copy()
    plot_df = plot_df.sort_values(value_col, ascending=True)

    fig, ax = plt.subplots(figsize=(10, max(6.0, 0.45 * len(plot_df))))
    ax.barh(
        plot_df[label_col],
        plot_df[value_col],
        color=party_colors(plot_df[party_col]),
    )

    ax.set_xlabel("Number of panel participations")
    ax.set_ylabel("Judge")

    xmax = plot_df[value_col].max()
    ax.set_xlim(0, xmax * 1.18)

    apply_common_style(ax)
    format_plain_numbers(ax)
    add_horizontal_value_labels(ax, plot_df[value_col])

    unique_parties = list(dict.fromkeys(plot_df[party_col]))
    cmap = party_color_map()
    legend_elements = [
        Patch(facecolor=cmap.get(party, "tab:orange"), label=party)
        for party in unique_parties
    ]
    ax.legend(
        handles=legend_elements,
        title="Political party",
        loc="lower right",
        frameon=False,
    )

    plt.tight_layout()
    plt.savefig(FIG_DIR / outfile, dpi=300, bbox_inches="tight")
    plt.close()


def main() -> None:
    panel = read_csv("top25_judges_by_panel_participation_with_party.csv")
    panel["full_name"] = panel["full_name"].astype(str).str.strip()

    save_top_panel_participation_plot(
        panel,
        label_col="full_name",
        value_col="panel_participation_count",
        party_col="political_party_clean",
        outfile="top15_judges_by_panel_participation_with_party.png",
        top_n=15,
    )

    print(f"Saved plot to: {FIG_DIR}")


if __name__ == "__main__":
    main()