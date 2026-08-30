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


def shorten_labels(series: pd.Series, max_len: int = 55) -> pd.Series:
    return series.astype(str).apply(
        lambda s: s if len(s) <= max_len else s[: max_len - 3] + "..."
    )


def format_plain_numbers(ax, axis: str = "y") -> None:
    if axis == "y":
        ax.ticklabel_format(style="plain", axis="y")
        ax.yaxis.set_major_formatter(mticker.StrMethodFormatter("{x:,.0f}"))
    elif axis == "x":
        ax.ticklabel_format(style="plain", axis="x")
        ax.xaxis.set_major_formatter(mticker.StrMethodFormatter("{x:,.0f}"))


def apply_common_style(ax, grid_axis: str = "y") -> None:
    ax.grid(axis=grid_axis, linestyle=":", linewidth=0.8, alpha=0.5)
    ax.set_axisbelow(True)


def save_bar_plot(
    df: pd.DataFrame,
    category_col: str,
    value_col: str,
    outfile: str,
    xlabel: str,
    ylabel: str,
    horizontal: bool = False,
    rotate_x: bool = False,
    sort_desc: bool = True,
    top_n: int | None = None,
) -> None:
    plot_df = df.copy()

    plot_df[value_col] = pd.to_numeric(plot_df[value_col], errors="coerce")
    plot_df = plot_df.dropna(subset=[value_col])

    if top_n is not None:
        plot_df = plot_df.head(top_n)

    plot_df = plot_df.sort_values(value_col, ascending=not sort_desc)

    if horizontal:
        plot_df = plot_df.sort_values(value_col, ascending=True)
        fig, ax = plt.subplots(figsize=(10, max(5.5, 0.45 * len(plot_df))))
        ax.barh(plot_df[category_col].astype(str), plot_df[value_col])

        ax.set_xlabel(xlabel)
        ax.set_ylabel(ylabel)

        apply_common_style(ax, grid_axis="x")
        format_plain_numbers(ax, axis="x")

    else:
        fig, ax = plt.subplots(figsize=(10, 6))
        ax.bar(plot_df[category_col].astype(str), plot_df[value_col])

        ax.set_xlabel(xlabel)
        ax.set_ylabel(ylabel)

        apply_common_style(ax, grid_axis="y")
        format_plain_numbers(ax, axis="y")

        if rotate_x:
            plt.xticks(rotation=45, ha="right")

    plt.tight_layout()
    plt.savefig(FIG_DIR / outfile, dpi=300, bbox_inches="tight")
    plt.close()


def main() -> None:
    # 1. Top clusters by citations
    top_clusters = read_csv("top20_clusters_by_citations.csv")
    top_clusters["case_name"] = shorten_labels(top_clusters["case_name"], max_len=60)
    top_clusters = top_clusters.sort_values("citation_count", ascending=True)

    save_bar_plot(
        top_clusters,
        category_col="case_name",
        value_col="citation_count",
        outfile="top20_clusters_by_citations.png",
        xlabel="Number of citations",
        ylabel="Opinion cluster",
        horizontal=True,
        sort_desc=True,
    )

    print(f"Saved heavy plots to: {FIG_DIR}")


if __name__ == "__main__":
    main()