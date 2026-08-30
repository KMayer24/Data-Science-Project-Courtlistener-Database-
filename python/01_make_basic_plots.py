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


def clean_category(series: pd.Series, missing_label: str = "Missing") -> pd.Series:
    return (
        series.astype("string")
        .fillna(missing_label)
        .replace({"<NA>": missing_label, "nan": missing_label, "None": missing_label})
        .str.strip()
        .replace("", missing_label)
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
    top_n: int | None = None,
    sort_desc: bool = True,
) -> None:
    plot_df = df.copy()

    plot_df[value_col] = pd.to_numeric(plot_df[value_col], errors="coerce")
    plot_df = plot_df.dropna(subset=[value_col])

    if category_col in plot_df.columns:
        plot_df[category_col] = clean_category(plot_df[category_col])

    plot_df = plot_df.sort_values(value_col, ascending=not sort_desc)

    if top_n is not None:
        plot_df = plot_df.head(top_n)

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
        plt.xticks(rotation=45, ha="right")

    plt.tight_layout()
    plt.savefig(FIG_DIR / outfile, dpi=300, bbox_inches="tight")
    plt.close()


def save_line_plot(
    df: pd.DataFrame,
    x_col: str,
    y_col: str,
    outfile: str,
    xlabel: str,
    ylabel: str,
    min_year: int | None = None,
    max_year: int | None = None,
) -> None:
    plot_df = df.copy()
    plot_df[x_col] = pd.to_numeric(plot_df[x_col], errors="coerce")
    plot_df[y_col] = pd.to_numeric(plot_df[y_col], errors="coerce")
    plot_df = plot_df.dropna(subset=[x_col, y_col])

    if min_year is not None:
        plot_df = plot_df[plot_df[x_col] >= min_year]
    if max_year is not None:
        plot_df = plot_df[plot_df[x_col] <= max_year]

    plot_df = plot_df.sort_values(by=x_col)
    plot_df[x_col] = plot_df[x_col].astype(int)

    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(plot_df[x_col], plot_df[y_col])

    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)

    ax.grid(axis="both", linestyle=":", linewidth=0.8, alpha=0.5)
    ax.set_axisbelow(True)

    format_plain_numbers(ax, axis="y")
    ax.xaxis.set_major_formatter(mticker.StrMethodFormatter("{x:.0f}"))

    plt.tight_layout()
    plt.savefig(FIG_DIR / outfile, dpi=300, bbox_inches="tight")
    plt.close()


def main() -> None:
    opinion_types = read_csv("opinion_type_distribution.csv")
    save_bar_plot(
        opinion_types,
        category_col="type",
        value_col="n",
        outfile="opinion_type_distribution.png",
        xlabel="Opinion type",
        ylabel="Count",
        horizontal=False,
        sort_desc=True,
    )

    precedential = read_csv("precedential_status_distribution.csv")
    save_bar_plot(
        precedential,
        category_col="precedential_status",
        value_col="n",
        outfile="precedential_status_distribution.png",
        xlabel="Precedential status",
        ylabel="Count",
        horizontal=False,
        sort_desc=True,
    )

    opinioncluster_year = read_csv("opinioncluster_by_year.csv").rename(
        columns={"filing_year": "year"}
    )
    save_line_plot(
        opinioncluster_year,
        x_col="year",
        y_col="n",
        outfile="opinioncluster_by_year.png",
        xlabel="Filing year",
        ylabel="Number of opinion clusters",
        min_year=1800,
        max_year=2025,
    )

    dockets_year = read_csv("dockets_by_year.csv").rename(
        columns={"filing_year": "year"}
    )
    save_line_plot(
        dockets_year,
        x_col="year",
        y_col="n",
        outfile="dockets_by_year.png",
        xlabel="Filing year",
        ylabel="Number of dockets",
        min_year=1800,
        max_year=2025,
    )

    top_courts = read_csv("top20_courts_by_dockets.csv")
    save_bar_plot(
        top_courts,
        category_col="full_name",
        value_col="docket_count",
        outfile="top20_courts_by_dockets.png",
        xlabel="Number of dockets",
        ylabel="Court",
        horizontal=True,
        sort_desc=True,
    )

    print(f"Saved plots to: {FIG_DIR}")


if __name__ == "__main__":
    main()